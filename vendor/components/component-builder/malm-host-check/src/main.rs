#![forbid(unsafe_code)]

use std::{collections::BTreeMap, env, error::Error, fs, io, path::Path};

use malm_config::{
    CanonicalTypedDocumentV1, DeclaredTransformResourceV1, RichKeyV1, RichNameV1, TargetPathV1,
    TransformFailureKindV1, TransformOptionV1, TransformRequestV1, TypedValueV1,
};
use malm_format_component_api::FormatComponentAuthorizationV1;
use malm_format_component_host::{FormatComponentHost, execution_profile_digest_v1};
use malm_types::Digest;

type Result<T> = std::result::Result<T, Box<dyn Error>>;

fn main() -> Result<()> {
    let mut args = env::args();
    let _program = args.next();
    match (args.next().as_deref(), args.next(), args.next()) {
        (Some("profile-digest"), None, None) => {
            println!("{}", execution_profile_digest_v1());
            Ok(())
        }
        (Some("verify-render-lua-data"), Some(component), None) => {
            verify_render_lua_data(Path::new(&component))
        }
        _ => Err(invalid(
            "usage: malm-host-check profile-digest | verify-render-lua-data COMPONENT",
        )),
    }
}

fn verify_render_lua_data(path: &Path) -> Result<()> {
    let bytes = fs::read(path)?;
    let digest = Digest::sha256(&bytes);
    let host = FormatComponentHost::new()?;
    if host.execution_profile_digest() != &execution_profile_digest_v1() {
        return Err(invalid(
            "Malm host profile identity is internally inconsistent",
        ));
    }
    let admitted = host.admit_component(
        &FormatComponentAuthorizationV1::new([digest.clone()]),
        &digest,
        &bytes,
    )?;

    let key = |value| RichKeyV1::new(value).expect("host-check key is valid");
    let document = TypedValueV1::record(BTreeMap::from([
        (key("boolean"), TypedValueV1::boolean(true)),
        (
            key("collection"),
            TypedValueV1::collection(BTreeMap::from([(
                key("entry"),
                TypedValueV1::string("value")?,
            )]))?,
        ),
        (key("end"), TypedValueV1::boolean(false)),
        (key("float"), TypedValueV1::float(1.0)?),
        (key("hyphen-key"), TypedValueV1::string("bracket")?),
        (key("integer"), TypedValueV1::integer(-2)),
        (
            key("list"),
            TypedValueV1::list(vec![
                TypedValueV1::unsigned(3),
                TypedValueV1::string("item")?,
            ])?,
        ),
        (
            key("path"),
            TypedValueV1::path(TargetPathV1::new("config/file")?),
        ),
        (
            key("record"),
            TypedValueV1::record(BTreeMap::from([(
                key("nested"),
                TypedValueV1::string("text")?,
            )]))?,
        ),
        (
            key("string"),
            TypedValueV1::string("line\n\"quote\"\\slash\0")?,
        ),
        (key("unsigned"), TypedValueV1::unsigned(i64::MAX as u64)),
    ]))?;
    let response = expect_success(admitted.transform(&lua_request(
        document,
        vec![lua_option("format", TypedValueV1::string("lua")?)?],
        Vec::new(),
    )?)?)?;
    let expected = concat!(
        "return {\n",
        "    boolean = true,\n",
        "    collection = {\n",
        "        entry = \"value\",\n",
        "    },\n",
        "    [\"end\"] = false,\n",
        "    float = 1.0,\n",
        "    [\"hyphen-key\"] = \"bracket\",\n",
        "    integer = -2,\n",
        "    list = {\n",
        "        3,\n",
        "        \"item\",\n",
        "    },\n",
        "    path = \"config/file\",\n",
        "    record = {\n",
        "        nested = \"text\",\n",
        "    },\n",
        "    string = \"line\\n\\\"quote\\\"\\\\slash\\x00\",\n",
        "    unsigned = 9223372036854775807,\n",
        "}\n",
    );
    if response.output() != expected.as_bytes() || response.media_type() != "text/x-lua" {
        return Err(invalid("render-lua-data response does not match"));
    }

    expect_failure(
        &admitted,
        lua_request(empty_record()?, Vec::new(), Vec::new())?,
        TransformFailureKindV1::InvalidRequest,
    )?;
    expect_failure(
        &admitted,
        lua_request(
            empty_record()?,
            vec![lua_option("format", TypedValueV1::string("json")?)?],
            Vec::new(),
        )?,
        TransformFailureKindV1::InvalidRequest,
    )?;
    expect_failure(
        &admitted,
        lua_request(
            empty_record()?,
            vec![lua_option("format", TypedValueV1::boolean(true))?],
            Vec::new(),
        )?,
        TransformFailureKindV1::InvalidRequest,
    )?;
    expect_failure(
        &admitted,
        lua_request(
            empty_record()?,
            vec![
                lua_option("format", TypedValueV1::string("lua")?)?,
                lua_option("extra", TypedValueV1::string("value")?)?,
            ],
            Vec::new(),
        )?,
        TransformFailureKindV1::InvalidRequest,
    )?;
    expect_failure(
        &admitted,
        lua_request(
            empty_record()?,
            vec![lua_option("format", TypedValueV1::string("lua")?)?],
            vec![DeclaredTransformResourceV1::capture(
                RichNameV1::new("content")?,
                b"unexpected",
            )?],
        )?,
        TransformFailureKindV1::InvalidRequest,
    )?;
    expect_failure(
        &admitted,
        lua_request(
            TypedValueV1::record(BTreeMap::from([(key("null"), TypedValueV1::null())]))?,
            vec![lua_option("format", TypedValueV1::string("lua")?)?],
            Vec::new(),
        )?,
        TransformFailureKindV1::InvalidRequest,
    )?;
    expect_failure(
        &admitted,
        lua_request(
            TypedValueV1::record(BTreeMap::from([(
                key("unsigned"),
                TypedValueV1::unsigned((i64::MAX as u64) + 1),
            )]))?,
            vec![lua_option("format", TypedValueV1::string("lua")?)?],
            Vec::new(),
        )?,
        TransformFailureKindV1::InvalidRequest,
    )?;

    println!(
        "Malm admitted and invoked {} ({digest}, profile {})",
        path.display(),
        host.execution_profile_digest()
    );
    Ok(())
}

fn lua_request(
    root: TypedValueV1,
    options: Vec<TransformOptionV1>,
    resources: Vec<DeclaredTransformResourceV1>,
) -> Result<TransformRequestV1> {
    Ok(TransformRequestV1::new(
        CanonicalTypedDocumentV1::new(root)?,
        options,
        resources,
    )?)
}

fn lua_option(name: &str, value: TypedValueV1) -> Result<TransformOptionV1> {
    Ok(TransformOptionV1::new(RichNameV1::new(name)?, value)?)
}

fn empty_record() -> Result<TypedValueV1> {
    Ok(TypedValueV1::record(BTreeMap::new())?)
}

fn expect_failure(
    component: &malm_format_component_host::AdmittedFormatComponent,
    request: TransformRequestV1,
    expected: TransformFailureKindV1,
) -> Result<()> {
    let failure = match component.transform(&request)? {
        Ok(_) => return Err(invalid("malformed request unexpectedly succeeded")),
        Err(failure) => failure,
    };
    if failure.kind() != expected {
        return Err(invalid(format!(
            "expected {expected:?} transform failure, found {:?}",
            failure.kind()
        )));
    }
    Ok(())
}

fn expect_success(
    result: std::result::Result<malm_config::TransformResponseV1, malm_config::TransformFailureV1>,
) -> Result<malm_config::TransformResponseV1> {
    result.map_err(|failure| {
        invalid(format!(
            "transform unexpectedly failed with {:?}: {}",
            failure.kind(),
            failure.message()
        ))
    })
}

fn invalid(message: impl Into<String>) -> Box<dyn Error> {
    Box::new(io::Error::new(io::ErrorKind::InvalidData, message.into()))
}
