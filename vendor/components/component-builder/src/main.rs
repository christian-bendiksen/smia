#![forbid(unsafe_code)]

use std::{
    env,
    error::Error,
    ffi::OsString,
    fmt::Write as _,
    fs, io,
    path::{Path, PathBuf},
};

use sha2::{Digest, Sha256};
use wasmparser::{ComponentExternalKind, Parser, Payload, Validator, WasmFeatures};
use wit_component::{ComponentEncoder, DecodedWasm, WitPrinter};
use wit_parser::{
    FunctionKind, Resolve, Type, TypeDefKind, UnresolvedPackageGroup, WorldId, WorldItem,
};

const EXPECTED_WIT_DIGEST: &str =
    "sha256-477f47ee29fdcc820c0819e71a2eddd5b5ea108c447faaa4df99ef2921d75b96";
const WORLD: &str = "malm-format-component";
const PACKAGE: &str = "malm:format-component@1.0.0";

type Result<T> = std::result::Result<T, Box<dyn Error>>;

fn main() -> Result<()> {
    let mut args = env::args_os();
    let _program = args.next();
    let Some(command) = args.next().and_then(|value| value.into_string().ok()) else {
        return Err(usage());
    };
    match command.as_str() {
        "pack" => {
            let [core, output] = paths(args)?;
            pack(&core, &output)
        }
        "verify" => {
            let [component, wit] = paths(args)?;
            verify(&component, &wit)
        }
        "manifest-named" => {
            let [component, wit, profile, name, output] = five_args(args)?;
            manifest(
                Path::new(&component),
                Path::new(&wit),
                &profile.to_string_lossy(),
                &name.to_string_lossy(),
                Path::new(&output),
            )
        }
        _ => Err(usage()),
    }
}

fn paths<const N: usize>(args: impl Iterator<Item = OsString>) -> Result<[PathBuf; N]> {
    let values = args.map(PathBuf::from).collect::<Vec<_>>();
    values.try_into().map_err(|_| usage())
}

fn five_args(args: impl Iterator<Item = OsString>) -> Result<[OsString; 5]> {
    let values = args.collect::<Vec<_>>();
    values.try_into().map_err(|_| usage())
}

fn usage() -> Box<dyn Error> {
    invalid(
        "usage: component-builder pack CORE OUTPUT | verify COMPONENT WIT | manifest-named COMPONENT WIT PROFILE NAME OUTPUT",
    )
}

fn pack(core_path: &Path, output_path: &Path) -> Result<()> {
    let core = fs::read(core_path)?;
    if !Parser::is_core_wasm(&core) {
        return Err(invalid(format!(
            "{} is not a core WebAssembly module",
            core_path.display()
        )));
    }
    let component = ComponentEncoder::default()
        .module(&core)?
        .validate(true)
        .encode()?;
    verify_root_shape(&component)?;
    fs::write(output_path, component)?;
    Ok(())
}

fn verify(component_path: &Path, wit_path: &Path) -> Result<()> {
    let component = fs::read(component_path)?;
    let wit_bytes = fs::read(wit_path)?;
    if sha256(&wit_bytes) != EXPECTED_WIT_DIGEST {
        return Err(invalid(format!(
            "WIT digest does not match {EXPECTED_WIT_DIGEST}"
        )));
    }
    if !Parser::is_component(&component) {
        return Err(invalid(format!(
            "{} is not a WebAssembly component",
            component_path.display()
        )));
    }
    Validator::new_with_features(WasmFeatures::all()).validate_all(&component)?;
    verify_root_shape(&component)?;

    let wit_source = std::str::from_utf8(&wit_bytes)?;
    let (source_resolve, source_package, source_world) = parse_wit(wit_path, wit_source)?;
    verify_world(&source_resolve, source_world, false)?;

    let DecodedWasm::Component(component_resolve, component_world) =
        wit_component::decode_reader(component.as_slice())?
    else {
        return Err(invalid("component decoded as a WIT package"));
    };
    verify_world(&component_resolve, component_world, true)?;
    let component_package = component_resolve.worlds[component_world]
        .package
        .ok_or_else(|| invalid("decoded component world has no package"))?;
    let source_text = normalize_source_identity(canonical_wit(&source_resolve, source_package)?);
    let component_text = canonical_wit(&component_resolve, component_package)?;
    if source_text != component_text {
        return Err(invalid(
            "component interface is not the exact vendored WIT interface",
        ));
    }
    Ok(())
}

fn verify_root_shape(component: &[u8]) -> Result<()> {
    let mut depth = 0_u32;
    let mut imports = Vec::new();
    let mut exports = Vec::new();

    for payload in Parser::new(0).parse_all(component) {
        match payload? {
            Payload::ModuleSection { .. } | Payload::ComponentSection { .. } => {
                depth = depth
                    .checked_add(1)
                    .ok_or_else(|| invalid("component nesting overflow"))?;
            }
            Payload::End(_) if depth > 0 => depth -= 1,
            Payload::ComponentImportSection(section) if depth == 0 => {
                for import in section {
                    let import = import?;
                    if !matches!(import.ty, wasmparser::ComponentTypeRef::Type(_)) {
                        imports.push(import.name.0.to_owned());
                    }
                }
            }
            Payload::ComponentExportSection(section) if depth == 0 => {
                for export in section {
                    let export = export?;
                    exports.push((export.name.0.to_owned(), export.kind));
                }
            }
            _ => {}
        }
    }

    if !imports.is_empty() {
        return Err(invalid(format!(
            "component has {} non-type root imports: {}",
            imports.len(),
            imports.join(", ")
        )));
    }
    if exports.as_slice() != [("transform".to_owned(), ComponentExternalKind::Func)] {
        return Err(invalid(format!(
            "root exports must be exactly one function named transform; found {exports:?}"
        )));
    }
    Ok(())
}

fn parse_wit(path: &Path, source: &str) -> Result<(Resolve, wit_parser::PackageId, WorldId)> {
    let group = UnresolvedPackageGroup::parse(path, source)?;
    let mut resolve = Resolve::default();
    let package = resolve.push_group(group)?;
    let world = resolve.select_world(package, Some(WORLD))?;
    Ok((resolve, package, world))
}

fn verify_world(resolve: &Resolve, world_id: WorldId, decoded_component: bool) -> Result<()> {
    let world = &resolve.worlds[world_id];
    let package = world
        .package
        .ok_or_else(|| invalid("component world has no package"))?;
    let (expected_world, expected_package) = if decoded_component {
        ("root", "root:component")
    } else {
        (WORLD, PACKAGE)
    };
    if world.name != expected_world {
        return Err(invalid(format!(
            "component world must be `{expected_world}`, found `{}`",
            world.name
        )));
    }
    if resolve.packages[package].name.to_string() != expected_package {
        return Err(invalid(format!(
            "component package must be `{expected_package}`"
        )));
    }
    if !world
        .imports
        .values()
        .all(|item| matches!(item, WorldItem::Type(_)))
    {
        return Err(invalid("component WIT world declares a capability import"));
    }
    if world.exports.len() != 1 {
        return Err(invalid("component WIT world must have one export"));
    }
    let (name, item) = world
        .exports
        .iter()
        .next()
        .ok_or_else(|| invalid("component WIT world has no transform export"))?;
    if resolve.name_world_key(name) != "transform" {
        return Err(invalid("sole WIT export must be named transform"));
    }
    let WorldItem::Function(transform) = item else {
        return Err(invalid("transform WIT export is not a function"));
    };
    if transform.kind != FunctionKind::Freestanding {
        return Err(invalid("transform WIT export is not freestanding"));
    }
    let params = transform
        .params
        .iter()
        .map(|(name, ty)| (name.as_str(), type_shape(resolve, *ty)))
        .collect::<Vec<_>>();
    if params != [("request", "transform-request-v1".to_owned())] {
        return Err(invalid("transform WIT request type does not match v1"));
    }
    let result = transform
        .result
        .map(|ty| type_shape(resolve, ty))
        .ok_or_else(|| invalid("transform WIT export has no result"))?;
    if result != "result<transform-response-v1,transform-failure-v1>" {
        return Err(invalid("transform WIT result type does not match v1"));
    }
    Ok(())
}

fn canonical_wit(resolve: &Resolve, package: wit_parser::PackageId) -> Result<String> {
    let mut printer = WitPrinter::default();
    printer.print(resolve, package, &[])?;
    Ok(printer.output.to_string())
}

fn normalize_source_identity(source: String) -> String {
    source
        .replacen(&format!("package {PACKAGE};"), "package root:component;", 1)
        .replacen(&format!("world {WORLD} {{"), "world root {", 1)
}

fn type_shape(resolve: &Resolve, ty: Type) -> String {
    match ty {
        Type::Bool => "bool".to_owned(),
        Type::U8 => "u8".to_owned(),
        Type::U16 => "u16".to_owned(),
        Type::U32 => "u32".to_owned(),
        Type::U64 => "u64".to_owned(),
        Type::S8 => "s8".to_owned(),
        Type::S16 => "s16".to_owned(),
        Type::S32 => "s32".to_owned(),
        Type::S64 => "s64".to_owned(),
        Type::F32 => "f32".to_owned(),
        Type::F64 => "f64".to_owned(),
        Type::Char => "char".to_owned(),
        Type::String => "string".to_owned(),
        Type::ErrorContext => "error-context".to_owned(),
        Type::Id(id) => {
            let definition = &resolve.types[id];
            if let Some(name) = &definition.name {
                return name.clone();
            }
            match &definition.kind {
                TypeDefKind::List(inner) => format!("list<{}>", type_shape(resolve, *inner)),
                TypeDefKind::Option(inner) => {
                    format!("option<{}>", type_shape(resolve, *inner))
                }
                TypeDefKind::Result(result) => format!(
                    "result<{},{}>",
                    result
                        .ok
                        .map(|ty| type_shape(resolve, ty))
                        .unwrap_or_else(|| "_".to_owned()),
                    result
                        .err
                        .map(|ty| type_shape(resolve, ty))
                        .unwrap_or_else(|| "_".to_owned())
                ),
                kind => format!("<anonymous-{kind:?}>"),
            }
        }
    }
}

fn manifest(
    component_path: &Path,
    wit_path: &Path,
    profile: &str,
    component_name: &str,
    output: &Path,
) -> Result<()> {
    if !valid_digest(profile) {
        return Err(invalid("Malm execution profile is not a SHA-256 digest"));
    }
    if !valid_component_name(component_name) {
        return Err(invalid("component manifest name is invalid"));
    }
    let component = fs::read(component_path)?;
    let wit = fs::read(wit_path)?;
    let wit_digest = sha256(&wit);
    if wit_digest != EXPECTED_WIT_DIGEST {
        return Err(invalid(format!(
            "WIT digest does not match {EXPECTED_WIT_DIGEST}"
        )));
    }
    let mut text = String::new();
    writeln!(&mut text, "{{")?;
    writeln!(&mut text, "  \"schema\": 1,")?;
    writeln!(&mut text, "  \"component\": \"{component_name}\",")?;
    writeln!(&mut text, "  \"raw_sha256\": \"{}\",", sha256(&component))?;
    writeln!(&mut text, "  \"wit_sha256\": \"{wit_digest}\",")?;
    writeln!(
        &mut text,
        "  \"malm_execution_profile_sha256\": \"{profile}\""
    )?;
    writeln!(&mut text, "}}")?;
    fs::write(output, text)?;
    Ok(())
}

fn valid_component_name(value: &str) -> bool {
    let Some(stem) = value.strip_suffix(".wasm") else {
        return false;
    };
    !stem.is_empty()
        && stem.bytes().all(|byte| {
            byte.is_ascii_lowercase() || byte.is_ascii_digit() || matches!(byte, b'-' | b'_')
        })
}

fn valid_digest(value: &str) -> bool {
    value.len() == 71
        && value.starts_with("sha256-")
        && value[7..]
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

fn sha256(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";

    let digest = Sha256::digest(bytes);
    let mut value = String::with_capacity(71);
    value.push_str("sha256-");
    for byte in digest {
        value.push(char::from(HEX[usize::from(byte >> 4)]));
        value.push(char::from(HEX[usize::from(byte & 0x0f)]));
    }
    value
}

fn invalid(message: impl Into<String>) -> Box<dyn Error> {
    Box::new(io::Error::new(io::ErrorKind::InvalidData, message.into()))
}
