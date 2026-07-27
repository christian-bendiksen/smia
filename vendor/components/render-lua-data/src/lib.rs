#![allow(
    clippy::too_many_arguments,
    reason = "wit-bindgen emits the fixed canonical ABI signatures"
)]

use std::collections::BTreeSet;

mod bindings {
    wit_bindgen::generate!({
        world: "malm-format-component",
        path: "wit",
    });
}

use bindings::{
    CanonicalValueV1, TransformFailureKindV1, TransformFailureV1, TransformRequestV1,
    TransformResponseV1, TypedValueV1, ValueFieldV1,
};

const CONTRACT_VERSION: u32 = 1;
const DOCUMENT_VERSION: u32 = 1;
const FORMAT_OPTION: &str = "format";
const FORMAT: &str = "lua";
const MEDIA_TYPE: &str = "text/x-lua";

// These are the format-component/v1 contract limits enforced by Malm v0.4.0.
const MAX_DEPTH: usize = 64;
const MAX_ITEMS: usize = 16_384;
const MAX_VALUES: usize = 262_144;
const MAX_TEXT_BYTES: usize = 1024 * 1024;
const MAX_KEY_BYTES: usize = 1024;
const MAX_PATH_BYTES: usize = 4096;
const MAX_PATH_SEGMENTS: usize = 64;
const MAX_ARENA_BYTES: usize = 64 * 1024 * 1024;
const MAX_OUTPUT_BYTES: usize = 64 * 1024 * 1024;

struct RenderLuaData;

impl bindings::Guest for RenderLuaData {
    fn transform(request: TransformRequestV1) -> Result<TransformResponseV1, TransformFailureV1> {
        transform(request)
    }
}

bindings::export!(RenderLuaData with_types_in bindings);

fn transform(request: TransformRequestV1) -> Result<TransformResponseV1, TransformFailureV1> {
    let TransformRequestV1 {
        contract_version,
        document,
        options,
        resources,
    } = request;
    if contract_version != CONTRACT_VERSION {
        return Err(invalid_request(format!(
            "contract-version must be {CONTRACT_VERSION}"
        )));
    }
    if document.version != DOCUMENT_VERSION {
        return Err(invalid_request(format!(
            "document version must be {DOCUMENT_VERSION}"
        )));
    }
    if !resources.is_empty() {
        return Err(invalid_request("render-lua-data does not accept resources"));
    }
    if options.len() != 1 || options[0].name != FORMAT_OPTION {
        return Err(invalid_request(
            "exactly one string option `format=lua` is required",
        ));
    }

    let option = &options[0].value;
    let option_arena = Arena::validate(option)?;
    if !matches!(option_arena.root(), TypedValueV1::Text(value) if value == FORMAT) {
        return Err(invalid_request(
            "exactly one string option `format=lua` is required",
        ));
    }

    let arena = Arena::validate(&document.root)?;
    if !matches!(arena.root(), TypedValueV1::RecordValue(_)) {
        return Err(invalid_request("document root must be a record"));
    }

    let mut output = Output::new(MAX_OUTPUT_BYTES);
    output.push_str("return ")?;
    render_value(&arena, document.root.root, 0, &mut output)?;
    output.push_str("\n")?;
    Ok(TransformResponseV1 {
        output: output.finish(),
        media_type: MEDIA_TYPE.to_owned(),
        diagnostics: Vec::new(),
    })
}

struct Arena<'a> {
    value: &'a CanonicalValueV1,
}

impl<'a> Arena<'a> {
    fn validate(value: &'a CanonicalValueV1) -> Result<Self, TransformFailureV1> {
        if value.values.len() > MAX_VALUES {
            return Err(resource_limit(format!(
                "canonical arena exceeds {MAX_VALUES} values"
            )));
        }
        let root = usize::try_from(value.root)
            .ok()
            .filter(|root| *root < value.values.len())
            .ok_or_else(|| invalid_request("canonical arena root ID is invalid"))?;

        let mut charged = 0_usize;
        for node in &value.values {
            charge(&mut charged, 1)?;
            match node {
                TypedValueV1::NullValue => {
                    return Err(invalid_request("null values are not supported"));
                }
                TypedValueV1::Boolean(_) => charge(&mut charged, 1)?,
                TypedValueV1::Signed(_) => charge(&mut charged, 8)?,
                TypedValueV1::Unsigned(number) => {
                    if *number > i64::MAX as u64 {
                        return Err(invalid_request("unsigned values must not exceed i64::MAX"));
                    }
                    charge(&mut charged, 8)?;
                }
                TypedValueV1::FloatingPoint(number) => {
                    if !number.is_finite() {
                        return Err(invalid_request("floating-point values must be finite"));
                    }
                    charge(&mut charged, 8)?;
                }
                TypedValueV1::Text(text) => {
                    if text.len() > MAX_TEXT_BYTES {
                        return Err(resource_limit(format!(
                            "text exceeds {MAX_TEXT_BYTES} bytes"
                        )));
                    }
                    charge(&mut charged, 8_usize.saturating_add(text.len()))?;
                }
                TypedValueV1::Path(path) => {
                    validate_path(path)?;
                    charge(&mut charged, 8_usize.saturating_add(path.len()))?;
                }
                TypedValueV1::ListValue(children) => {
                    validate_items("list", children.len())?;
                    charge(&mut charged, 8_usize.saturating_add(children.len() * 4))?;
                    validate_ids(children.iter().copied(), value.values.len())?;
                }
                TypedValueV1::RecordValue(fields) => {
                    validate_fields("record", fields, value.values.len(), &mut charged)?;
                }
                TypedValueV1::CollectionValue(fields) => {
                    validate_fields("collection", fields, value.values.len(), &mut charged)?;
                }
            }
        }

        let arena = Self { value };
        let mut states = vec![Visit::Unseen; value.values.len()];
        arena.visit(root, 1, &mut states)?;
        if states.contains(&Visit::Unseen) {
            return Err(invalid_request(
                "canonical arena contains an unreachable value",
            ));
        }
        Ok(arena)
    }

    fn root(&self) -> &TypedValueV1 {
        &self.value.values[self.value.root as usize]
    }

    fn get(&self, id: u32) -> &TypedValueV1 {
        &self.value.values[id as usize]
    }

    fn visit(
        &self,
        id: usize,
        depth: usize,
        states: &mut [Visit],
    ) -> Result<(), TransformFailureV1> {
        if depth > MAX_DEPTH {
            return Err(resource_limit(format!(
                "canonical arena exceeds depth {MAX_DEPTH}"
            )));
        }
        match states[id] {
            Visit::Visiting => return Err(invalid_request("canonical arena contains a cycle")),
            Visit::Visited => {
                return Err(invalid_request("canonical arena contains an aliased value"));
            }
            Visit::Unseen => states[id] = Visit::Visiting,
        }

        let children = match self.get(id as u32) {
            TypedValueV1::ListValue(children) => children.clone(),
            TypedValueV1::RecordValue(fields) | TypedValueV1::CollectionValue(fields) => {
                fields.iter().map(|field| field.value).collect()
            }
            _ => Vec::new(),
        };
        for child in children {
            self.visit(child as usize, depth + 1, states)?;
        }
        states[id] = Visit::Visited;
        Ok(())
    }
}

#[derive(Clone, Copy, Eq, PartialEq)]
enum Visit {
    Unseen,
    Visiting,
    Visited,
}

fn validate_items(kind: &str, actual: usize) -> Result<(), TransformFailureV1> {
    if actual > MAX_ITEMS {
        return Err(resource_limit(format!("{kind} exceeds {MAX_ITEMS} items")));
    }
    Ok(())
}

fn validate_ids(
    ids: impl Iterator<Item = u32>,
    value_count: usize,
) -> Result<(), TransformFailureV1> {
    if ids.map(|id| id as usize).any(|id| id >= value_count) {
        return Err(invalid_request(
            "canonical arena contains an invalid value ID",
        ));
    }
    Ok(())
}

fn validate_fields(
    kind: &str,
    fields: &[ValueFieldV1],
    value_count: usize,
    charged: &mut usize,
) -> Result<(), TransformFailureV1> {
    validate_items(kind, fields.len())?;
    let mut names = BTreeSet::new();
    for field in fields {
        if field.name.is_empty() || field.name.chars().any(char::is_control) {
            return Err(invalid_request(format!("{kind} contains an invalid key")));
        }
        if field.name.len() > MAX_KEY_BYTES {
            return Err(resource_limit(format!(
                "{kind} key exceeds {MAX_KEY_BYTES} bytes"
            )));
        }
        if !names.insert(field.name.as_str()) {
            return Err(invalid_request(format!(
                "{kind} contains duplicate key `{}`",
                field.name
            )));
        }
        charge(charged, 12_usize.saturating_add(field.name.len()))?;
    }
    validate_ids(fields.iter().map(|field| field.value), value_count)
}

fn validate_path(path: &str) -> Result<(), TransformFailureV1> {
    if path.len() > MAX_PATH_BYTES {
        return Err(resource_limit(format!(
            "path exceeds {MAX_PATH_BYTES} bytes"
        )));
    }
    if path.is_empty()
        || path.starts_with('/')
        || path.contains('\\')
        || path.chars().any(char::is_control)
    {
        return Err(invalid_request("path value is not canonical"));
    }
    let mut segments = 0_usize;
    for segment in path.split('/') {
        segments += 1;
        if segment.is_empty() || matches!(segment, "." | "..") {
            return Err(invalid_request("path value is not canonical"));
        }
        if segment.len() > 255 {
            return Err(resource_limit("path segment exceeds 255 bytes"));
        }
    }
    if segments > MAX_PATH_SEGMENTS {
        return Err(resource_limit(format!(
            "path exceeds {MAX_PATH_SEGMENTS} segments"
        )));
    }
    Ok(())
}

fn charge(total: &mut usize, amount: usize) -> Result<(), TransformFailureV1> {
    *total = total.saturating_add(amount);
    if *total > MAX_ARENA_BYTES {
        return Err(resource_limit(format!(
            "canonical arena exceeds {MAX_ARENA_BYTES} bytes"
        )));
    }
    Ok(())
}

fn render_value(
    arena: &Arena<'_>,
    id: u32,
    depth: usize,
    output: &mut Output,
) -> Result<(), TransformFailureV1> {
    match arena.get(id) {
        TypedValueV1::NullValue => unreachable!("null was rejected during validation"),
        TypedValueV1::Boolean(value) => output.push_str(if *value { "true" } else { "false" }),
        TypedValueV1::Signed(i64::MIN) => output.push_str("(-9223372036854775807 - 1)"),
        TypedValueV1::Signed(value) => output.push_str(&value.to_string()),
        TypedValueV1::Unsigned(value) => output.push_str(&value.to_string()),
        TypedValueV1::FloatingPoint(value) => render_float(*value, output),
        TypedValueV1::Text(value) | TypedValueV1::Path(value) => render_string(value, output),
        TypedValueV1::ListValue(values) => render_list(arena, values, depth, output),
        TypedValueV1::RecordValue(fields) | TypedValueV1::CollectionValue(fields) => {
            render_map(arena, fields, depth, output)
        }
    }
}

fn render_float(value: f64, output: &mut Output) -> Result<(), TransformFailureV1> {
    if value == 0.0 {
        return output.push_str("0.0");
    }
    let mut rendered = value.to_string();
    if !rendered
        .bytes()
        .any(|byte| matches!(byte, b'.' | b'e' | b'E'))
    {
        rendered.push_str(".0");
    }
    output.push_str(&rendered)
}

fn render_list(
    arena: &Arena<'_>,
    values: &[u32],
    depth: usize,
    output: &mut Output,
) -> Result<(), TransformFailureV1> {
    output.push_str("{\n")?;
    for value in values {
        output.indent(depth + 1)?;
        render_value(arena, *value, depth + 1, output)?;
        output.push_str(",\n")?;
    }
    output.indent(depth)?;
    output.push_str("}")
}

fn render_map(
    arena: &Arena<'_>,
    fields: &[ValueFieldV1],
    depth: usize,
    output: &mut Output,
) -> Result<(), TransformFailureV1> {
    let mut fields = fields.iter().collect::<Vec<_>>();
    fields.sort_unstable_by(|left, right| left.name.cmp(&right.name));

    output.push_str("{\n")?;
    for field in fields {
        output.indent(depth + 1)?;
        render_key(&field.name, output)?;
        output.push_str(" = ")?;
        render_value(arena, field.value, depth + 1, output)?;
        output.push_str(",\n")?;
    }
    output.indent(depth)?;
    output.push_str("}")
}

fn render_key(key: &str, output: &mut Output) -> Result<(), TransformFailureV1> {
    if is_lua_identifier(key) && !is_lua_keyword(key) {
        output.push_str(key)
    } else {
        output.push_str("[")?;
        render_string(key, output)?;
        output.push_str("]")
    }
}

fn is_lua_identifier(value: &str) -> bool {
    let Some((&first, rest)) = value.as_bytes().split_first() else {
        return false;
    };
    (first.is_ascii_alphabetic() || first == b'_')
        && rest
            .iter()
            .all(|byte| byte.is_ascii_alphanumeric() || *byte == b'_')
}

fn is_lua_keyword(value: &str) -> bool {
    matches!(
        value,
        "and"
            | "break"
            | "do"
            | "else"
            | "elseif"
            | "end"
            | "false"
            | "for"
            | "function"
            | "goto"
            | "if"
            | "in"
            | "local"
            | "nil"
            | "not"
            | "or"
            | "repeat"
            | "return"
            | "then"
            | "true"
            | "until"
            | "while"
    )
}

fn render_string(value: &str, output: &mut Output) -> Result<(), TransformFailureV1> {
    output.push_str("\"")?;
    for character in value.chars() {
        match character {
            '"' => output.push_str("\\\"")?,
            '\\' => output.push_str("\\\\")?,
            '\u{7}' => output.push_str("\\a")?,
            '\u{8}' => output.push_str("\\b")?,
            '\t' => output.push_str("\\t")?,
            '\n' => output.push_str("\\n")?,
            '\u{b}' => output.push_str("\\v")?,
            '\u{c}' => output.push_str("\\f")?,
            '\r' => output.push_str("\\r")?,
            '\0'..='\u{1f}' | '\u{7f}' => render_byte_escape(character as u8, output)?,
            character if character.is_control() => render_unicode_escape(character, output)?,
            character => {
                let mut encoded = [0_u8; 4];
                output.push_str(character.encode_utf8(&mut encoded))?;
            }
        }
    }
    output.push_str("\"")
}

fn render_byte_escape(value: u8, output: &mut Output) -> Result<(), TransformFailureV1> {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let escaped = [
        b'\\',
        b'x',
        HEX[usize::from(value >> 4)],
        HEX[usize::from(value & 0x0f)],
    ];
    output.push_bytes(&escaped)
}

fn render_unicode_escape(value: char, output: &mut Output) -> Result<(), TransformFailureV1> {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut number = value as u32;
    let mut reversed = [0_u8; 6];
    let mut length = 0;
    loop {
        reversed[length] = HEX[(number & 0x0f) as usize];
        length += 1;
        number >>= 4;
        if number == 0 {
            break;
        }
    }
    output.push_str("\\u{")?;
    for byte in reversed[..length].iter().rev() {
        output.push_bytes(&[*byte])?;
    }
    output.push_str("}")
}

struct Output {
    bytes: Vec<u8>,
    limit: usize,
}

impl Output {
    fn new(limit: usize) -> Self {
        Self {
            bytes: Vec::new(),
            limit,
        }
    }

    fn push_str(&mut self, value: &str) -> Result<(), TransformFailureV1> {
        self.push_bytes(value.as_bytes())
    }

    fn push_bytes(&mut self, value: &[u8]) -> Result<(), TransformFailureV1> {
        if self.bytes.len().saturating_add(value.len()) > self.limit {
            return Err(resource_limit(format!(
                "Lua output exceeds {} bytes",
                self.limit
            )));
        }
        self.bytes.extend_from_slice(value);
        Ok(())
    }

    fn indent(&mut self, depth: usize) -> Result<(), TransformFailureV1> {
        for _ in 0..depth {
            self.push_str("    ")?;
        }
        Ok(())
    }

    fn finish(self) -> Vec<u8> {
        self.bytes
    }
}

fn invalid_request(message: impl Into<String>) -> TransformFailureV1 {
    failure(TransformFailureKindV1::InvalidRequest, message)
}

fn resource_limit(message: impl Into<String>) -> TransformFailureV1 {
    failure(TransformFailureKindV1::ResourceLimit, message)
}

fn failure(kind: TransformFailureKindV1, message: impl Into<String>) -> TransformFailureV1 {
    TransformFailureV1 {
        kind,
        message: message.into(),
        diagnostics: Vec::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use bindings::{CanonicalTypedDocumentV1, DeclaredResourceV1, TransformOptionV1, ValueFieldV1};

    fn canonical(root: u32, values: Vec<TypedValueV1>) -> CanonicalValueV1 {
        CanonicalValueV1 { root, values }
    }

    fn field(name: &str, value: u32) -> ValueFieldV1 {
        ValueFieldV1 {
            name: name.to_owned(),
            value,
        }
    }

    fn request(root: CanonicalValueV1) -> TransformRequestV1 {
        TransformRequestV1 {
            contract_version: CONTRACT_VERSION,
            document: CanonicalTypedDocumentV1 {
                version: DOCUMENT_VERSION,
                root,
                source_documents: Vec::new(),
                includes: Vec::new(),
                provenance: Vec::new(),
            },
            options: vec![TransformOptionV1 {
                name: FORMAT_OPTION.to_owned(),
                value: canonical(0, vec![TypedValueV1::Text(FORMAT.to_owned())]),
            }],
            resources: Vec::new(),
        }
    }

    fn kind(result: Result<TransformResponseV1, TransformFailureV1>) -> TransformFailureKindV1 {
        result.expect_err("request must fail").kind
    }

    #[test]
    fn renders_every_supported_value_in_canonical_order() {
        let root = canonical(
            14,
            vec![
                TypedValueV1::Boolean(true),
                TypedValueV1::Text("value".to_owned()),
                TypedValueV1::CollectionValue(vec![field("entry", 1)]),
                TypedValueV1::Boolean(false),
                TypedValueV1::FloatingPoint(1.5),
                TypedValueV1::Text("bracket".to_owned()),
                TypedValueV1::Signed(-2),
                TypedValueV1::Unsigned(3),
                TypedValueV1::Path("config/file".to_owned()),
                TypedValueV1::Text("item".to_owned()),
                TypedValueV1::ListValue(vec![7, 9]),
                TypedValueV1::Text("line\n\"quote\"\\slash\0".to_owned()),
                TypedValueV1::FloatingPoint(-0.0),
                TypedValueV1::RecordValue(vec![field("nested", 12)]),
                TypedValueV1::RecordValue(vec![
                    field("string", 11),
                    field("record", 13),
                    field("path", 8),
                    field("list", 10),
                    field("integer", 6),
                    field("hyphen-key", 5),
                    field("float", 4),
                    field("end", 3),
                    field("collection", 2),
                    field("boolean", 0),
                ]),
            ],
        );

        let response = transform(request(root)).expect("valid document renders");
        assert_eq!(response.media_type, MEDIA_TYPE);
        assert!(response.diagnostics.is_empty());
        assert_eq!(
            String::from_utf8(response.output).unwrap(),
            concat!(
                "return {\n",
                "    boolean = true,\n",
                "    collection = {\n",
                "        entry = \"value\",\n",
                "    },\n",
                "    [\"end\"] = false,\n",
                "    float = 1.5,\n",
                "    [\"hyphen-key\"] = \"bracket\",\n",
                "    integer = -2,\n",
                "    list = {\n",
                "        3,\n",
                "        \"item\",\n",
                "    },\n",
                "    path = \"config/file\",\n",
                "    record = {\n",
                "        nested = 0.0,\n",
                "    },\n",
                "    string = \"line\\n\\\"quote\\\"\\\\slash\\x00\",\n",
                "}\n",
            )
        );
    }

    #[test]
    fn renders_float_and_string_edges_deterministically() {
        let arena = canonical(
            8,
            vec![
                TypedValueV1::FloatingPoint(1.0),
                TypedValueV1::FloatingPoint(1e100),
                TypedValueV1::FloatingPoint(f64::MIN_POSITIVE),
                TypedValueV1::Signed(i64::MIN),
                TypedValueV1::Unsigned(i64::MAX as u64),
                TypedValueV1::Text("\u{80}\u{e9}".to_owned()),
                TypedValueV1::Text("controls\u{1}\u{7}\u{b}\u{7f}".to_owned()),
                TypedValueV1::Text("identifier".to_owned()),
                TypedValueV1::RecordValue(vec![
                    field("a", 0),
                    field("b", 1),
                    field("c", 2),
                    field("d", 3),
                    field("e", 4),
                    field("f", 5),
                    field("g", 6),
                    field("_valid9", 7),
                ]),
            ],
        );
        let output = String::from_utf8(transform(request(arena)).unwrap().output).unwrap();
        assert!(output.contains("a = 1.0,"));
        let mut large_float = 1e100_f64.to_string();
        if !large_float
            .bytes()
            .any(|byte| matches!(byte, b'.' | b'e' | b'E'))
        {
            large_float.push_str(".0");
        }
        assert!(output.contains(&format!("b = {large_float},")));
        assert!(output.contains("d = (-9223372036854775807 - 1),"));
        assert!(output.contains("e = 9223372036854775807,"));
        assert!(output.contains("f = \"\\u{80}é\","));
        assert!(output.contains("g = \"controls\\x01\\a\\v\\x7f\","));
    }

    #[test]
    fn rejects_contract_shape_errors() {
        let empty_record = || canonical(0, vec![TypedValueV1::RecordValue(Vec::new())]);

        let mut bad = request(empty_record());
        bad.contract_version = 2;
        assert!(matches!(
            kind(transform(bad)),
            TransformFailureKindV1::InvalidRequest
        ));

        let mut bad = request(empty_record());
        bad.document.version = 2;
        assert!(matches!(
            kind(transform(bad)),
            TransformFailureKindV1::InvalidRequest
        ));

        let mut bad = request(empty_record());
        bad.options.clear();
        assert!(matches!(
            kind(transform(bad)),
            TransformFailureKindV1::InvalidRequest
        ));

        let mut bad = request(empty_record());
        bad.options[0].value.values[0] = TypedValueV1::Text("json".to_owned());
        assert!(matches!(
            kind(transform(bad)),
            TransformFailureKindV1::InvalidRequest
        ));

        let mut bad = request(empty_record());
        bad.resources.push(DeclaredResourceV1 {
            name: "content".to_owned(),
            digest: "sha256-00".to_owned(),
            bytes: Vec::new(),
        });
        assert!(matches!(
            kind(transform(bad)),
            TransformFailureKindV1::InvalidRequest
        ));

        assert!(matches!(
            kind(transform(request(canonical(
                0,
                vec![TypedValueV1::Boolean(true)]
            )))),
            TransformFailureKindV1::InvalidRequest
        ));
    }

    #[test]
    fn rejects_invalid_ids_cycles_aliases_unreachable_values_and_duplicate_keys() {
        let cases = [
            canonical(0, vec![TypedValueV1::ListValue(vec![1])]),
            canonical(0, vec![TypedValueV1::ListValue(vec![0])]),
            canonical(
                1,
                vec![
                    TypedValueV1::Boolean(true),
                    TypedValueV1::ListValue(vec![0, 0]),
                ],
            ),
            canonical(
                1,
                vec![
                    TypedValueV1::RecordValue(Vec::new()),
                    TypedValueV1::RecordValue(Vec::new()),
                ],
            ),
            canonical(
                2,
                vec![
                    TypedValueV1::Boolean(true),
                    TypedValueV1::Boolean(false),
                    TypedValueV1::RecordValue(vec![field("same", 0), field("same", 1)]),
                ],
            ),
        ];
        for arena in cases {
            assert!(matches!(
                kind(transform(request(arena))),
                TransformFailureKindV1::InvalidRequest
            ));
        }
    }

    #[test]
    fn rejects_unsupported_values_and_noncanonical_paths() {
        for value in [
            TypedValueV1::NullValue,
            TypedValueV1::Unsigned((i64::MAX as u64) + 1),
            TypedValueV1::FloatingPoint(f64::NAN),
            TypedValueV1::FloatingPoint(f64::INFINITY),
            TypedValueV1::Path("../escape".to_owned()),
            TypedValueV1::Path("/absolute".to_owned()),
        ] {
            let arena = canonical(
                1,
                vec![value, TypedValueV1::RecordValue(vec![field("value", 0)])],
            );
            assert!(matches!(
                kind(transform(request(arena))),
                TransformFailureKindV1::InvalidRequest
            ));
        }
    }

    #[test]
    fn reports_depth_item_value_and_output_limits() {
        let mut values = vec![TypedValueV1::RecordValue(Vec::new())];
        for id in 0..MAX_DEPTH {
            values.push(TypedValueV1::RecordValue(vec![field("nested", id as u32)]));
        }
        assert!(matches!(
            kind(transform(request(canonical(MAX_DEPTH as u32, values)))),
            TransformFailureKindV1::ResourceLimit
        ));

        let too_many_items = vec![0; MAX_ITEMS + 1];
        let arena = canonical(
            1,
            vec![
                TypedValueV1::Boolean(true),
                TypedValueV1::ListValue(too_many_items),
            ],
        );
        let failure = match Arena::validate(&arena) {
            Ok(_) => panic!("oversized list must fail"),
            Err(failure) => failure,
        };
        assert!(matches!(
            failure.kind,
            TransformFailureKindV1::ResourceLimit
        ));

        let arena = canonical(0, vec![TypedValueV1::Boolean(true); MAX_VALUES + 1]);
        let failure = match Arena::validate(&arena) {
            Ok(_) => panic!("oversized arena must fail"),
            Err(failure) => failure,
        };
        assert!(matches!(
            failure.kind,
            TransformFailureKindV1::ResourceLimit
        ));

        let arena = canonical(0, vec![TypedValueV1::RecordValue(Vec::new())]);
        let arena = Arena::validate(&arena).unwrap();
        let mut output = Output::new(2);
        let failure = render_value(&arena, 0, 0, &mut output).unwrap_err();
        assert!(matches!(
            failure.kind,
            TransformFailureKindV1::ResourceLimit
        ));
    }
}
