use std::{
    collections::{BTreeMap, BTreeSet},
    env,
    error::Error,
    ffi::OsStr,
    fs::{self, File, OpenOptions},
    io::{Cursor, Read, Write},
    path::{Component, Path, PathBuf},
    process::{Command, Stdio},
};

use malm_archive::{
    ARCHIVE_DECODER_IDENTITY_V1, ArchiveLimitsV1, USTAR_BLOCK_BYTES, decode_posix_ustar_v1,
};
use malm_tree::file_object_digest_v1;
use malm_types::Digest;
use serde::{Deserialize, Serialize};

const SOURCE_MANIFEST: &str = "vendor/upstream/sources.json";
const PROVENANCE_INVENTORY: &str = "vendor/upstream/provenance.json";
const ARCHIVE_DIRECTORY: &str = "vendor/upstream";
const MAX_MANIFEST_BYTES: u64 = 1024 * 1024;
const MAX_COMPRESSED_BYTES: u64 = 384 * 1024 * 1024;
const MAX_EXPANDED_BYTES: u64 = 384 * 1024 * 1024;
const MAX_ARCHIVE_BYTES: u64 = 384 * 1024 * 1024;
const MAX_FILE_BYTES: u64 = 256 * 1024 * 1024;
const MAX_ENTRIES: usize = 100_000;

type DynError = Box<dyn Error>;
type Result<T> = std::result::Result<T, DynError>;

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
struct DecoderSpec {
    name: String,
    version: u16,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct SourceManifestV1 {
    schema_version: u16,
    decoder: DecoderSpec,
    remote_sources: Vec<RemoteSource>,
    local_sources: Vec<LocalSource>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RemoteSource {
    id: String,
    url: String,
    vendored_path: String,
    compressed_sha256: String,
    outputs: Vec<RemoteOutput>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct RemoteOutput {
    id: String,
    source_subpath: String,
    archive_path: String,
    destination: String,
    executable_paths: Vec<String>,
}

#[derive(Debug, Deserialize)]
#[serde(deny_unknown_fields)]
struct LocalSource {
    id: String,
    path: String,
    archive_path: String,
    destination: String,
    executable_paths: Vec<String>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
struct ProvenanceInventoryV1 {
    schema_version: u16,
    decoder: DecoderSpec,
    archives: Vec<ArchiveInventory>,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(deny_unknown_fields)]
struct ArchiveInventory {
    id: String,
    archive_path: String,
    destination: String,
    source_id: String,
    source_kind: String,
    source_path: String,
    source_subpath: String,
    source_digest_kind: String,
    source_digest: String,
    raw_archive_digest: String,
    raw_archive_byte_len: u64,
    malm_file_object_digest: String,
    canonical_tree_digest: String,
    tree_entries: u64,
    tree_file_bytes: u64,
    tree_max_depth: u64,
}

#[derive(Clone, Debug)]
enum TreeEntry {
    Directory,
    File(Vec<u8>),
}

#[derive(Clone, Debug, Default)]
struct SourceTree {
    entries: BTreeMap<String, TreeEntry>,
}

struct BuiltArchive {
    bytes: Vec<u8>,
    inventory: ArchiveInventory,
}

struct ComputedAssets {
    archives: Vec<BuiltArchive>,
    provenance: ProvenanceInventoryV1,
}

struct ArchiveIdentity {
    raw_digest: Digest,
    file_object_digest: Digest,
    tree_digest: Digest,
    entries: u64,
    file_bytes: u64,
    max_depth: u64,
}

fn main() {
    if let Err(error) = run() {
        eprintln!("vendor-assets: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let command = env::args().nth(1).unwrap_or_else(|| "verify".to_owned());
    let repo = repository_root()?;
    let manifest = load_source_manifest(&repo)?;
    validate_source_manifest(&manifest)?;

    match command.as_str() {
        "fetch" => fetch_sources(&repo, &manifest),
        "generate" => {
            let computed = compute_assets(&repo, &manifest)?;
            write_assets(&repo, &computed)?;
            verify_assets(&repo, &computed)?;
            print_verified(&computed);
            Ok(())
        }
        "verify" => {
            let computed = compute_assets(&repo, &manifest)?;
            verify_assets(&repo, &computed)?;
            print_verified(&computed);
            Ok(())
        }
        _ => fail("usage: vendor-assets {fetch|generate|verify}"),
    }
}

fn repository_root() -> Result<PathBuf> {
    let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
    manifest_dir
        .parent()
        .and_then(Path::parent)
        .map(Path::to_path_buf)
        .ok_or_else(|| invalid_data("tool is not under tools/vendor-assets"))
}

fn load_source_manifest(repo: &Path) -> Result<SourceManifestV1> {
    let bytes = read_regular_file_bounded(&repo.join(SOURCE_MANIFEST), MAX_MANIFEST_BYTES)?;
    serde_json::from_slice(&bytes).map_err(Into::into)
}

fn validate_source_manifest(manifest: &SourceManifestV1) -> Result<()> {
    if manifest.schema_version != 1 {
        return fail(format!(
            "unsupported source manifest schema {}",
            manifest.schema_version
        ));
    }
    let decoder = ARCHIVE_DECODER_IDENTITY_V1;
    if manifest.decoder.name != decoder.name() || manifest.decoder.version != decoder.version() {
        return fail("source manifest does not select the current Malm archive/v1 decoder");
    }
    let mut source_ids = BTreeSet::new();
    let mut output_ids = BTreeSet::new();
    let mut source_paths = BTreeSet::new();
    let mut archive_paths = BTreeSet::new();
    let mut destinations = BTreeSet::new();
    for source in &manifest.remote_sources {
        require_unique(&mut source_ids, &source.id, "source id")?;
        validate_https_url(&source.url)?;
        validate_relative_path(&source.vendored_path)?;
        if !source.vendored_path.starts_with("vendor/upstream/")
            || !source.vendored_path.ends_with(".tar.xz")
        {
            return fail(format!(
                "remote source {} must be a vendor/upstream/*.tar.xz path",
                source.id
            ));
        }
        require_unique(&mut source_paths, &source.vendored_path, "source path")?;
        Digest::new(&source.compressed_sha256).map_err(|error| {
            invalid_data(format!(
                "invalid compressed digest for {}: {error}",
                source.id
            ))
        })?;
        if source.outputs.is_empty() {
            return fail(format!("remote source {} has no outputs", source.id));
        }
        let mut subpaths = BTreeSet::new();
        for output in &source.outputs {
            require_unique(&mut output_ids, &output.id, "output id")?;
            require_unique(&mut subpaths, &output.source_subpath, "extraction subpath")?;
            validate_tree_path(&output.source_subpath)?;
            validate_output(output, &mut archive_paths, &mut destinations)?;
        }
    }
    for source in &manifest.local_sources {
        require_unique(&mut source_ids, &source.id, "source id")?;
        require_unique(&mut output_ids, &source.id, "output id")?;
        validate_relative_path(&source.path)?;
        if !source.path.starts_with("gnist/themes/data/") {
            return fail(format!("local source {} is not a Gnist theme", source.id));
        }
        require_unique(&mut source_paths, &source.path, "source path")?;
        validate_output(source, &mut archive_paths, &mut destinations)?;
    }
    Ok(())
}

trait OutputSpec {
    fn archive_path(&self) -> &str;
    fn destination(&self) -> &str;
    fn executable_paths(&self) -> &[String];
}

impl OutputSpec for RemoteOutput {
    fn archive_path(&self) -> &str {
        &self.archive_path
    }

    fn destination(&self) -> &str {
        &self.destination
    }

    fn executable_paths(&self) -> &[String] {
        &self.executable_paths
    }
}

impl OutputSpec for LocalSource {
    fn archive_path(&self) -> &str {
        &self.archive_path
    }

    fn destination(&self) -> &str {
        &self.destination
    }

    fn executable_paths(&self) -> &[String] {
        &self.executable_paths
    }
}

fn validate_output<T: OutputSpec>(
    output: &T,
    archive_paths: &mut BTreeSet<String>,
    destinations: &mut BTreeSet<String>,
) -> Result<()> {
    validate_relative_path(output.archive_path())?;
    if !output
        .archive_path()
        .starts_with(&format!("{ARCHIVE_DIRECTORY}/"))
        || Path::new(output.archive_path()).extension() != Some(OsStr::new("tar"))
        || Path::new(output.archive_path()).parent() != Some(Path::new(ARCHIVE_DIRECTORY))
    {
        return fail(format!(
            "archive output must be a direct {ARCHIVE_DIRECTORY}/*.tar path: {}",
            output.archive_path()
        ));
    }
    require_unique(archive_paths, output.archive_path(), "archive path")?;
    validate_relative_path(output.destination())?;
    require_unique(destinations, output.destination(), "destination")?;
    let mut executable_paths = BTreeSet::new();
    for path in output.executable_paths() {
        validate_tree_path(path)?;
        require_unique(&mut executable_paths, path, "executable path")?;
    }
    Ok(())
}

fn require_unique(set: &mut BTreeSet<String>, value: &str, kind: &str) -> Result<()> {
    if set.insert(value.to_owned()) {
        Ok(())
    } else {
        fail(format!("duplicate {kind} {value:?}"))
    }
}

fn validate_https_url(url: &str) -> Result<()> {
    if url.starts_with("https://") && !url.chars().any(char::is_control) {
        Ok(())
    } else {
        fail(format!(
            "source URL is not a control-free HTTPS URL: {url:?}"
        ))
    }
}

fn fetch_sources(repo: &Path, manifest: &SourceManifestV1) -> Result<()> {
    for source in &manifest.remote_sources {
        let destination = repo.join(&source.vendored_path);
        if destination.exists() {
            validate_compressed_source(source, &destination)?;
            println!("present {} {}", source.id, source.compressed_sha256);
            continue;
        }
        let parent = destination
            .parent()
            .ok_or_else(|| invalid_data("vendored source has no parent"))?;
        create_directory(parent)?;
        let temporary = temporary_path(&destination);
        let status = Command::new("curl")
            .args([
                "--fail",
                "--location",
                "--proto",
                "=https",
                "--tlsv1.2",
                "--max-filesize",
                &MAX_COMPRESSED_BYTES.to_string(),
                "--output",
            ])
            .arg(&temporary)
            .arg(&source.url)
            .status()?;
        if !status.success() {
            let _ = fs::remove_file(&temporary);
            return fail(format!("curl failed while fetching {}", source.id));
        }
        if let Err(error) = validate_compressed_source(source, &temporary) {
            let _ = fs::remove_file(&temporary);
            return Err(error);
        }
        fs::rename(&temporary, &destination)?;
        set_file_mode(&destination, 0o644)?;
        println!("fetched {} {}", source.id, source.compressed_sha256);
    }
    Ok(())
}

fn validate_compressed_source(source: &RemoteSource, path: &Path) -> Result<(Vec<u8>, Digest)> {
    let bytes = read_regular_file_bounded(path, MAX_COMPRESSED_BYTES)?;
    let actual = Digest::sha256(&bytes);
    if actual.as_str() != source.compressed_sha256 {
        return fail(format!(
            "compressed digest mismatch for {}: expected {}, computed {}",
            source.id, source.compressed_sha256, actual
        ));
    }
    Ok((bytes, actual))
}

fn compute_assets(repo: &Path, manifest: &SourceManifestV1) -> Result<ComputedAssets> {
    let mut archives = Vec::new();
    for source in &manifest.remote_sources {
        let source_path = repo.join(&source.vendored_path);
        let (compressed, source_digest) = validate_compressed_source(source, &source_path)?;
        let expanded = decompress_xz_bounded(&source_path)?;
        let complete_tree = parse_upstream_tar(&expanded)?;
        validate_remote_roots(source, &complete_tree)?;
        for output in &source.outputs {
            let tree = complete_tree.subtree(&output.source_subpath)?;
            archives.push(build_archive(
                output.id.clone(),
                output.archive_path.clone(),
                output.destination.clone(),
                source.id.clone(),
                "remote-tar-xz",
                source.vendored_path.clone(),
                output.source_subpath.clone(),
                "compressed-payload-sha256",
                source_digest.as_str().to_owned(),
                &tree,
                &output.executable_paths,
            )?);
        }
        drop(compressed);
    }
    for source in &manifest.local_sources {
        let tree = read_local_tree(&repo.join(&source.path))?;
        let mut archive = build_archive(
            source.id.clone(),
            source.archive_path.clone(),
            source.destination.clone(),
            source.id.clone(),
            "local-tree",
            source.path.clone(),
            String::new(),
            "malm-tree-v1-sha256",
            String::new(),
            &tree,
            &source.executable_paths,
        )?;
        archive
            .inventory
            .source_digest
            .clone_from(&archive.inventory.canonical_tree_digest);
        archives.push(archive);
    }
    archives.sort_by(|left, right| {
        left.inventory
            .archive_path
            .cmp(&right.inventory.archive_path)
    });
    let provenance = ProvenanceInventoryV1 {
        schema_version: 1,
        decoder: manifest.decoder.clone(),
        archives: archives
            .iter()
            .map(|archive| archive.inventory.clone())
            .collect(),
    };
    Ok(ComputedAssets {
        archives,
        provenance,
    })
}

#[allow(clippy::too_many_arguments)]
fn build_archive(
    id: String,
    archive_path: String,
    destination: String,
    source_id: String,
    source_kind: &str,
    source_path: String,
    source_subpath: String,
    source_digest_kind: &str,
    source_digest: String,
    tree: &SourceTree,
    executable_paths: &[String],
) -> Result<BuiltArchive> {
    let executable_paths = executable_paths.iter().cloned().collect::<BTreeSet<_>>();
    for executable in &executable_paths {
        if !matches!(tree.entries.get(executable), Some(TreeEntry::File(_))) {
            return fail(format!(
                "declared executable {executable:?} in {id} is not a regular file"
            ));
        }
    }
    let bytes = encode_strict_ustar(tree, &executable_paths)?;
    audit_normalized_ustar(&bytes, tree, &executable_paths)?;
    let identity = inspect_with_malm(&bytes)?;
    let inventory = ArchiveInventory {
        id,
        archive_path,
        destination,
        source_id,
        source_kind: source_kind.to_owned(),
        source_path,
        source_subpath,
        source_digest_kind: source_digest_kind.to_owned(),
        source_digest,
        raw_archive_digest: identity.raw_digest.as_str().to_owned(),
        raw_archive_byte_len: bytes.len() as u64,
        malm_file_object_digest: identity.file_object_digest.as_str().to_owned(),
        canonical_tree_digest: identity.tree_digest.as_str().to_owned(),
        tree_entries: identity.entries,
        tree_file_bytes: identity.file_bytes,
        tree_max_depth: identity.max_depth,
    };
    Ok(BuiltArchive { bytes, inventory })
}

fn inspect_with_malm(bytes: &[u8]) -> Result<ArchiveIdentity> {
    if bytes.len() as u64 > MAX_ARCHIVE_BYTES {
        return fail(format!("archive exceeds {MAX_ARCHIVE_BYTES} bytes"));
    }
    let raw_digest = Digest::sha256(bytes);
    let file_object_digest = file_object_digest_v1(bytes)?;
    let limits = ArchiveLimitsV1 {
        max_payload_bytes: MAX_ARCHIVE_BYTES,
        max_read_operations: bytes.len() as u64 + 1,
        ..ArchiveLimitsV1::default()
    };
    let decoded = decode_posix_ustar_v1(
        Cursor::new(bytes),
        bytes.len() as u64,
        raw_digest.clone(),
        limits,
    )?;
    let summary = decoded.tree_graph().summary();
    Ok(ArchiveIdentity {
        raw_digest,
        file_object_digest,
        tree_digest: decoded.root_digest().clone(),
        entries: summary.entries() as u64,
        file_bytes: summary.file_bytes(),
        max_depth: summary.depth() as u64,
    })
}

fn validate_remote_roots(source: &RemoteSource, tree: &SourceTree) -> Result<()> {
    for path in tree.entries.keys() {
        if source.outputs.iter().any(|output| {
            path == &output.source_subpath
                || path
                    .strip_prefix(&output.source_subpath)
                    .is_some_and(|remainder| remainder.starts_with('/'))
        }) {
            continue;
        }
        return fail(format!(
            "upstream source {} has entry outside pinned extraction subpaths: {path:?}",
            source.id
        ));
    }
    Ok(())
}

impl SourceTree {
    fn insert(&mut self, path: impl Into<String>, entry: TreeEntry) -> Result<()> {
        let path = path.into();
        validate_tree_path(&path)?;
        if self.entries.len() >= MAX_ENTRIES {
            return fail(format!("source tree exceeds {MAX_ENTRIES} entries"));
        }
        if self.entries.insert(path.clone(), entry).is_some() {
            return fail(format!("duplicate source tree path {path:?}"));
        }
        Ok(())
    }

    fn subtree(&self, root: &str) -> Result<Self> {
        let prefix = format!("{root}/");
        if !matches!(self.entries.get(root), Some(TreeEntry::Directory)) {
            return fail(format!(
                "upstream extraction root {root:?} is not a directory"
            ));
        }
        let mut subtree = Self::default();
        for (path, entry) in &self.entries {
            if let Some(relative) = path.strip_prefix(&prefix) {
                subtree.insert(relative.to_owned(), entry.clone())?;
            }
        }
        if subtree.entries.is_empty() {
            return fail(format!("upstream extraction root {root:?} is empty"));
        }
        Ok(subtree)
    }
}

fn read_local_tree(root: &Path) -> Result<SourceTree> {
    let metadata = fs::symlink_metadata(root)?;
    if !metadata.file_type().is_dir() {
        return fail(format!(
            "local source is not a directory: {}",
            root.display()
        ));
    }
    let mut tree = SourceTree::default();
    let mut file_bytes = 0_u64;
    read_local_directory(root, root, &mut tree, &mut file_bytes)?;
    if tree.entries.is_empty() {
        return fail(format!("local source is empty: {}", root.display()));
    }
    Ok(tree)
}

fn read_local_directory(
    root: &Path,
    directory: &Path,
    tree: &mut SourceTree,
    file_bytes: &mut u64,
) -> Result<()> {
    let mut children = fs::read_dir(directory)?.collect::<std::io::Result<Vec<_>>>()?;
    children.sort_by(|left, right| {
        left.file_name()
            .as_encoded_bytes()
            .cmp(right.file_name().as_encoded_bytes())
    });
    for child in children {
        let path = child.path();
        let relative = path.strip_prefix(root)?;
        let relative = path_to_utf8_slashes(relative)?;
        let metadata = fs::symlink_metadata(&path)?;
        let file_type = metadata.file_type();
        if file_type.is_dir() {
            tree.insert(relative, TreeEntry::Directory)?;
            read_local_directory(root, &path, tree, file_bytes)?;
        } else if file_type.is_file() {
            if metadata.len() > MAX_FILE_BYTES {
                return fail(format!("source file is too large: {}", path.display()));
            }
            let bytes = read_regular_file_bounded(&path, MAX_FILE_BYTES)?;
            *file_bytes = file_bytes
                .checked_add(bytes.len() as u64)
                .ok_or_else(|| invalid_data("source file byte count overflow"))?;
            if *file_bytes > MAX_EXPANDED_BYTES {
                return fail(format!(
                    "source tree exceeds {MAX_EXPANDED_BYTES} file bytes"
                ));
            }
            tree.insert(relative, TreeEntry::File(bytes))?;
        } else {
            return fail(format!(
                "local source contains a link or special entry: {}",
                path.display()
            ));
        }
    }
    Ok(())
}

fn path_to_utf8_slashes(path: &Path) -> Result<String> {
    let mut value = String::new();
    for component in path.components() {
        let Component::Normal(segment) = component else {
            return fail(format!("noncanonical source path: {}", path.display()));
        };
        let segment = segment
            .to_str()
            .ok_or_else(|| invalid_data(format!("source path is not UTF-8: {}", path.display())))?;
        if !value.is_empty() {
            value.push('/');
        }
        value.push_str(segment);
    }
    validate_tree_path(&value)?;
    Ok(value)
}

fn decompress_xz_bounded(path: &Path) -> Result<Vec<u8>> {
    let mut child = Command::new("xz")
        .args(["--decompress", "--stdout", "--"])
        .arg(path)
        .env_remove("XZ_DEFAULTS")
        .env_remove("XZ_OPT")
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::inherit())
        .spawn()?;
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| invalid_data("xz stdout was not captured"))?;
    let mut bytes = Vec::new();
    stdout
        .take(MAX_EXPANDED_BYTES + 1)
        .read_to_end(&mut bytes)?;
    if bytes.len() as u64 > MAX_EXPANDED_BYTES {
        let _ = child.kill();
        let _ = child.wait();
        return fail(format!(
            "expanded source exceeds {MAX_EXPANDED_BYTES} bytes"
        ));
    }
    let status = child.wait()?;
    if !status.success() {
        return fail(format!("xz failed for {}", path.display()));
    }
    Ok(bytes)
}

fn parse_upstream_tar(bytes: &[u8]) -> Result<SourceTree> {
    if !bytes.len().is_multiple_of(USTAR_BLOCK_BYTES) {
        return fail("upstream tar length is not a multiple of 512 bytes");
    }
    let mut tree = SourceTree::default();
    let mut offset = 0_usize;
    let mut file_bytes = 0_u64;
    while offset < bytes.len() {
        let block: &[u8; USTAR_BLOCK_BYTES] = bytes[offset..offset + USTAR_BLOCK_BYTES]
            .try_into()
            .expect("block slice has fixed width");
        if block.iter().all(|byte| *byte == 0) {
            let remaining = &bytes[offset..];
            if remaining.len() < 2 * USTAR_BLOCK_BYTES || remaining.iter().any(|byte| *byte != 0) {
                return fail("upstream tar has a malformed terminator");
            }
            return Ok(tree);
        }
        verify_source_checksum(block, offset / USTAR_BLOCK_BYTES)?;
        let posix = &block[257..263] == b"ustar\0" && &block[263..265] == b"00";
        let gnu = &block[257..265] == b"ustar  \0";
        if !posix && !gnu {
            return fail(format!(
                "upstream tar block {} is not POSIX/GNU ustar",
                offset / USTAR_BLOCK_BYTES
            ));
        }
        let name = source_text_field(&block[0..100], "name")?;
        let prefix = if posix {
            source_text_field(&block[345..500], "prefix")?
        } else {
            ""
        };
        let mut path = if prefix.is_empty() {
            name.to_owned()
        } else {
            format!("{prefix}/{name}")
        };
        let size = source_octal(&block[124..136], "size")?;
        if size > MAX_FILE_BYTES {
            return fail(format!(
                "upstream file {path:?} exceeds {MAX_FILE_BYTES} bytes"
            ));
        }
        let body_start = offset + USTAR_BLOCK_BYTES;
        let body_len =
            usize::try_from(size).map_err(|_| invalid_data("tar size does not fit usize"))?;
        let body_end = body_start
            .checked_add(body_len)
            .ok_or_else(|| invalid_data("tar body offset overflow"))?;
        let padded_end = body_start
            .checked_add(round_up_512(body_len)?)
            .ok_or_else(|| invalid_data("tar padding offset overflow"))?;
        if padded_end > bytes.len() {
            return fail(format!("upstream tar entry {path:?} is truncated"));
        }
        if bytes[body_end..padded_end].iter().any(|byte| *byte != 0) {
            return fail(format!("upstream tar entry {path:?} has nonzero padding"));
        }
        match block[156] {
            0 | b'0' => {
                if path.ends_with('/') {
                    return fail(format!("regular file path ends in slash: {path:?}"));
                }
                file_bytes = file_bytes
                    .checked_add(size)
                    .ok_or_else(|| invalid_data("upstream file byte count overflow"))?;
                if file_bytes > MAX_EXPANDED_BYTES {
                    return fail(format!(
                        "upstream tree exceeds {MAX_EXPANDED_BYTES} logical file bytes"
                    ));
                }
                tree.insert(path, TreeEntry::File(bytes[body_start..body_end].to_vec()))?;
            }
            b'5' => {
                if size != 0 {
                    return fail(format!("upstream directory {path:?} has a body"));
                }
                if path.ends_with('/') {
                    path.pop();
                }
                tree.insert(path, TreeEntry::Directory)?;
            }
            kind => {
                return fail(format!(
                    "upstream tar contains forbidden link/special/extension type {kind:#04x} at {path:?}"
                ));
            }
        }
        offset = padded_end;
    }
    fail("upstream tar is missing its terminator")
}

fn source_text_field<'a>(field: &'a [u8], name: &str) -> Result<&'a str> {
    let end = field
        .iter()
        .position(|byte| *byte == 0)
        .unwrap_or(field.len());
    if field[end..].iter().any(|byte| *byte != 0) {
        return fail(format!("upstream tar {name} has bytes after NUL"));
    }
    std::str::from_utf8(&field[..end])
        .map_err(|_| invalid_data(format!("upstream tar {name} is not UTF-8")))
}

fn source_octal(field: &[u8], name: &str) -> Result<u64> {
    let field = field
        .iter()
        .copied()
        .skip_while(|byte| matches!(*byte, 0 | b' '))
        .take_while(|byte| !matches!(*byte, 0 | b' '))
        .collect::<Vec<_>>();
    if field.is_empty() || !field.iter().all(|byte| matches!(*byte, b'0'..=b'7')) {
        return fail(format!("upstream tar {name} is not octal"));
    }
    let text = std::str::from_utf8(&field).expect("octal digits are UTF-8");
    u64::from_str_radix(text, 8).map_err(|_| invalid_data(format!("upstream tar {name} overflows")))
}

fn verify_source_checksum(block: &[u8; USTAR_BLOCK_BYTES], index: usize) -> Result<()> {
    let stored = source_octal(&block[148..156], "checksum")?;
    let computed = block
        .iter()
        .enumerate()
        .map(|(offset, byte)| {
            if (148..156).contains(&offset) {
                u64::from(b' ')
            } else {
                u64::from(*byte)
            }
        })
        .sum::<u64>();
    if stored == computed {
        Ok(())
    } else {
        fail(format!(
            "upstream tar block {index} checksum mismatch: stored {stored:o}, computed {computed:o}"
        ))
    }
}

fn encode_strict_ustar(tree: &SourceTree, executable_paths: &BTreeSet<String>) -> Result<Vec<u8>> {
    let mut archive = Vec::new();
    for (path, entry) in &tree.entries {
        let (mode, size, typeflag) = match entry {
            TreeEntry::Directory => (0o755_u32, 0_u64, b'5'),
            TreeEntry::File(bytes) => (
                if executable_paths.contains(path) {
                    0o755
                } else {
                    0o644
                },
                bytes.len() as u64,
                b'0',
            ),
        };
        let header = ustar_header(path, mode, size, typeflag)?;
        archive.extend_from_slice(&header);
        if let TreeEntry::File(bytes) = entry {
            archive.extend_from_slice(bytes);
            let padding = padding_len(bytes.len());
            archive.resize(archive.len() + padding, 0);
        }
        if archive.len() as u64 > MAX_ARCHIVE_BYTES.saturating_sub(2 * USTAR_BLOCK_BYTES as u64) {
            return fail(format!(
                "generated archive exceeds {MAX_ARCHIVE_BYTES} bytes"
            ));
        }
    }
    archive.resize(archive.len() + 2 * USTAR_BLOCK_BYTES, 0);
    Ok(archive)
}

#[allow(clippy::too_many_lines)]
fn audit_normalized_ustar(
    bytes: &[u8],
    expected: &SourceTree,
    executable_paths: &BTreeSet<String>,
) -> Result<()> {
    if !bytes.len().is_multiple_of(USTAR_BLOCK_BYTES) {
        return fail("generated archive length is not a multiple of 512 bytes");
    }
    let mut offset = 0_usize;
    let mut previous_path: Option<String> = None;
    let mut observed = 0_usize;
    loop {
        if offset + 2 * USTAR_BLOCK_BYTES == bytes.len() {
            if bytes[offset..].iter().any(|byte| *byte != 0) {
                return fail("generated archive does not end in exactly two zero blocks");
            }
            break;
        }
        if offset + 2 * USTAR_BLOCK_BYTES > bytes.len() {
            return fail("generated archive is missing its exact two-block terminator");
        }
        let block: &[u8; USTAR_BLOCK_BYTES] = bytes[offset..offset + USTAR_BLOCK_BYTES]
            .try_into()
            .expect("block slice has fixed width");
        if block.iter().all(|byte| *byte == 0) {
            return fail("generated archive has early or extra terminal padding");
        }
        verify_source_checksum(block, offset / USTAR_BLOCK_BYTES)?;
        if &block[257..263] != b"ustar\0"
            || &block[263..265] != b"00"
            || block[500..512].iter().any(|byte| *byte != 0)
        {
            return fail("generated archive header is not strict POSIX ustar");
        }
        if !block[148..154]
            .iter()
            .all(|byte| matches!(*byte, b'0'..=b'7'))
            || block[154] != 0
            || block[155] != b' '
        {
            return fail("generated archive checksum field is not canonical");
        }
        let name = source_text_field(&block[0..100], "name")?;
        let prefix = source_text_field(&block[345..500], "prefix")?;
        let path = if prefix.is_empty() {
            name.to_owned()
        } else {
            format!("{prefix}/{name}")
        };
        validate_tree_path(&path)?;
        if previous_path
            .as_ref()
            .is_some_and(|previous| previous.as_bytes() >= path.as_bytes())
        {
            return fail(format!(
                "generated archive paths are not strictly UTF-8 byte sorted at {path:?}"
            ));
        }
        previous_path = Some(path.clone());
        let entry = expected
            .entries
            .get(&path)
            .ok_or_else(|| invalid_data(format!("unexpected generated path {path:?}")))?;
        let expected_mode = match entry {
            TreeEntry::Directory => 0o755,
            TreeEntry::File(_) if executable_paths.contains(&path) => 0o755,
            TreeEntry::File(_) => 0o644,
        };
        if strict_octal(&block[100..108], "mode")? != expected_mode
            || strict_octal(&block[108..116], "uid")? != 0
            || strict_octal(&block[116..124], "gid")? != 0
            || strict_octal(&block[136..148], "mtime")? != 0
        {
            return fail(format!(
                "generated archive metadata is not normalized at {path:?}"
            ));
        }
        if block[157..257].iter().any(|byte| *byte != 0)
            || block[265..345].iter().any(|byte| *byte != 0)
        {
            return fail(format!(
                "generated archive has noncanonical link/user/group/device metadata at {path:?}"
            ));
        }
        let size = strict_octal(&block[124..136], "size")?;
        let expected_body = match entry {
            TreeEntry::Directory if block[156] == b'5' && size == 0 => &[][..],
            TreeEntry::File(body) if block[156] == b'0' && size == body.len() as u64 => {
                body.as_slice()
            }
            TreeEntry::Directory => {
                return fail(format!("generated directory header is invalid at {path:?}"));
            }
            TreeEntry::File(_) => {
                return fail(format!(
                    "generated regular-file header is invalid at {path:?}"
                ));
            }
        };
        let body_start = offset + USTAR_BLOCK_BYTES;
        let body_end = body_start
            .checked_add(expected_body.len())
            .ok_or_else(|| invalid_data("generated archive body offset overflow"))?;
        let padded_end = body_start
            .checked_add(round_up_512(expected_body.len())?)
            .ok_or_else(|| invalid_data("generated archive padding offset overflow"))?;
        if padded_end > bytes.len()
            || &bytes[body_start..body_end] != expected_body
            || bytes[body_end..padded_end].iter().any(|byte| *byte != 0)
        {
            return fail(format!(
                "generated archive body or padding differs from source at {path:?}"
            ));
        }
        observed += 1;
        offset = padded_end;
    }
    if observed != expected.entries.len() {
        return fail(format!(
            "generated archive has {observed} entries; expected {}",
            expected.entries.len()
        ));
    }
    Ok(())
}

fn strict_octal(field: &[u8], name: &str) -> Result<u64> {
    let Some((&terminator, digits)) = field.split_last() else {
        return fail(format!("generated ustar {name} field is empty"));
    };
    if terminator != 0 || !digits.iter().all(|byte| matches!(*byte, b'0'..=b'7')) {
        return fail(format!(
            "generated ustar {name} field is not canonical octal"
        ));
    }
    let text = std::str::from_utf8(digits).expect("octal digits are UTF-8");
    u64::from_str_radix(text, 8)
        .map_err(|_| invalid_data(format!("generated ustar {name} field overflows")))
}

fn ustar_header(path: &str, mode: u32, size: u64, typeflag: u8) -> Result<[u8; USTAR_BLOCK_BYTES]> {
    validate_tree_path(path)?;
    let (name, prefix) = split_ustar_path(path)?;
    let mut header = [0_u8; USTAR_BLOCK_BYTES];
    copy_field(&mut header[0..100], name.as_bytes(), "name")?;
    write_octal(&mut header[100..108], u64::from(mode), "mode")?;
    write_octal(&mut header[108..116], 0, "uid")?;
    write_octal(&mut header[116..124], 0, "gid")?;
    write_octal(&mut header[124..136], size, "size")?;
    write_octal(&mut header[136..148], 0, "mtime")?;
    header[148..156].fill(b' ');
    header[156] = typeflag;
    header[257..263].copy_from_slice(b"ustar\0");
    header[263..265].copy_from_slice(b"00");
    copy_field(&mut header[345..500], prefix.as_bytes(), "prefix")?;
    let checksum = header.iter().map(|byte| u64::from(*byte)).sum::<u64>();
    write_checksum(&mut header[148..156], checksum)?;
    Ok(header)
}

fn split_ustar_path(path: &str) -> Result<(&str, &str)> {
    if path.len() <= 100 {
        return Ok((path, ""));
    }
    for (index, byte) in path.as_bytes().iter().enumerate().rev() {
        if *byte != b'/' {
            continue;
        }
        let prefix = &path[..index];
        let name = &path[index + 1..];
        if prefix.len() <= 155 && !name.is_empty() && name.len() <= 100 {
            return Ok((name, prefix));
        }
    }
    fail(format!(
        "path cannot be represented by POSIX ustar: {path:?}"
    ))
}

fn copy_field(target: &mut [u8], value: &[u8], name: &str) -> Result<()> {
    if value.len() > target.len() {
        return fail(format!("ustar {name} is too long"));
    }
    target[..value.len()].copy_from_slice(value);
    Ok(())
}

fn write_octal(target: &mut [u8], value: u64, name: &str) -> Result<()> {
    let width = target.len() - 1;
    let encoded = format!("{value:0width$o}");
    if encoded.len() != width {
        return fail(format!("ustar {name} value does not fit"));
    }
    target[..width].copy_from_slice(encoded.as_bytes());
    target[width] = 0;
    Ok(())
}

fn write_checksum(target: &mut [u8], value: u64) -> Result<()> {
    let encoded = format!("{value:06o}");
    if encoded.len() != 6 {
        return fail("ustar checksum does not fit");
    }
    target[..6].copy_from_slice(encoded.as_bytes());
    target[6] = 0;
    target[7] = b' ';
    Ok(())
}

fn write_assets(repo: &Path, computed: &ComputedAssets) -> Result<()> {
    create_directory(&repo.join(ARCHIVE_DIRECTORY))?;
    let provenance_path = repo.join(PROVENANCE_INVENTORY);
    let provenance_parent = provenance_path
        .parent()
        .ok_or_else(|| invalid_data("provenance path has no parent"))?;
    create_directory(provenance_parent)?;
    for archive in &computed.archives {
        write_if_changed(
            &repo.join(&archive.inventory.archive_path),
            &archive.bytes,
            MAX_ARCHIVE_BYTES,
        )?;
    }
    let mut provenance = serde_json::to_vec_pretty(&computed.provenance)?;
    provenance.push(b'\n');
    write_if_changed(
        &repo.join(PROVENANCE_INVENTORY),
        &provenance,
        MAX_MANIFEST_BYTES,
    )?;
    Ok(())
}

fn verify_assets(repo: &Path, computed: &ComputedAssets) -> Result<()> {
    let archive_directory = repo.join(ARCHIVE_DIRECTORY);
    let mut expected_names = BTreeSet::new();
    for expected in &computed.archives {
        let path = repo.join(&expected.inventory.archive_path);
        let actual = read_regular_file_bounded(&path, MAX_ARCHIVE_BYTES)?;
        let actual_identity = inspect_with_malm(&actual)?;
        if actual != expected.bytes {
            return fail(format!(
                "archive is not the deterministic source-derived payload: {}",
                expected.inventory.archive_path
            ));
        }
        if actual_identity.raw_digest.as_str() != expected.inventory.raw_archive_digest
            || actual_identity.file_object_digest.as_str()
                != expected.inventory.malm_file_object_digest
            || actual_identity.tree_digest.as_str() != expected.inventory.canonical_tree_digest
        {
            return fail(format!(
                "Malm identity mismatch for {}",
                expected.inventory.archive_path
            ));
        }
        let name = path
            .file_name()
            .and_then(OsStr::to_str)
            .ok_or_else(|| invalid_data("archive filename is not UTF-8"))?;
        expected_names.insert(name.to_owned());
    }
    let mut actual_names = BTreeSet::new();
    for entry in fs::read_dir(&archive_directory)? {
        let entry = entry?;
        let name = entry
            .file_name()
            .into_string()
            .map_err(|_| invalid_data("archive directory filename is not UTF-8"))?;
        if Path::new(&name).extension() == Some(OsStr::new("tar")) {
            if !entry.file_type()?.is_file() {
                return fail(format!("archive output is not a regular file: {name}"));
            }
            actual_names.insert(name);
        }
    }
    if actual_names != expected_names {
        return fail(format!(
            "archive directory inventory mismatch; expected={expected_names:?}, actual={actual_names:?}"
        ));
    }

    let provenance_path = repo.join(PROVENANCE_INVENTORY);
    let actual_bytes = read_regular_file_bounded(&provenance_path, MAX_MANIFEST_BYTES)?;
    let actual: ProvenanceInventoryV1 = serde_json::from_slice(&actual_bytes)?;
    if actual != computed.provenance {
        return fail("provenance inventory does not match current sources and archives");
    }
    let mut canonical = serde_json::to_vec_pretty(&computed.provenance)?;
    canonical.push(b'\n');
    if actual_bytes != canonical {
        return fail("provenance inventory JSON is not in canonical generated form");
    }
    Ok(())
}

fn print_verified(computed: &ComputedAssets) {
    for archive in &computed.archives {
        println!(
            "verified {} len={} raw={} object={} tree={}",
            archive.inventory.id,
            archive.inventory.raw_archive_byte_len,
            archive.inventory.raw_archive_digest,
            archive.inventory.malm_file_object_digest,
            archive.inventory.canonical_tree_digest
        );
    }
    println!(
        "verified {} deterministic archives",
        computed.archives.len()
    );
}

fn read_regular_file_bounded(path: &Path, limit: u64) -> Result<Vec<u8>> {
    let metadata = fs::symlink_metadata(path)?;
    if !metadata.file_type().is_file() {
        return fail(format!("path is not a regular file: {}", path.display()));
    }
    if metadata.len() > limit {
        return fail(format!(
            "file {} is {} bytes; limit is {limit}",
            path.display(),
            metadata.len()
        ));
    }
    let file = File::open(path)?;
    if !file.metadata()?.file_type().is_file() {
        return fail(format!(
            "opened path is not a regular file: {}",
            path.display()
        ));
    }
    let capacity = usize::try_from(metadata.len()).map_err(|_| {
        invalid_data(format!(
            "file length does not fit usize: {}",
            path.display()
        ))
    })?;
    let mut bytes = Vec::with_capacity(capacity);
    file.take(limit + 1).read_to_end(&mut bytes)?;
    if bytes.len() as u64 > limit {
        return fail(format!(
            "file grew beyond its {limit}-byte limit: {}",
            path.display()
        ));
    }
    Ok(bytes)
}

fn write_if_changed(path: &Path, bytes: &[u8], limit: u64) -> Result<bool> {
    if path.exists() && read_regular_file_bounded(path, limit)? == bytes {
        return Ok(false);
    }
    let parent = path
        .parent()
        .ok_or_else(|| invalid_data("output path has no parent"))?;
    create_directory(parent)?;
    let temporary = temporary_path(path);
    let mut file = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&temporary)?;
    file.write_all(bytes)?;
    file.sync_all()?;
    drop(file);
    set_file_mode(&temporary, 0o644)?;
    fs::rename(&temporary, path)?;
    Ok(true)
}

fn temporary_path(path: &Path) -> PathBuf {
    let mut name = path
        .file_name()
        .unwrap_or_else(|| OsStr::new("asset"))
        .to_os_string();
    name.push(format!(".tmp-{}", std::process::id()));
    path.with_file_name(name)
}

fn create_directory(path: &Path) -> Result<()> {
    fs::create_dir_all(path)?;
    set_file_mode(path, 0o755)
}

#[cfg(unix)]
fn set_file_mode(path: &Path, mode: u32) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(path, fs::Permissions::from_mode(mode))?;
    Ok(())
}

#[cfg(not(unix))]
fn set_file_mode(_path: &Path, _mode: u32) -> Result<()> {
    Ok(())
}

fn validate_relative_path(path: &str) -> Result<()> {
    if path.is_empty()
        || path.starts_with('/')
        || path.ends_with('/')
        || path.contains('\\')
        || path.chars().any(char::is_control)
    {
        return fail(format!("invalid repository-relative path {path:?}"));
    }
    if Path::new(path)
        .components()
        .any(|component| !matches!(component, Component::Normal(_)))
    {
        return fail(format!("noncanonical repository-relative path {path:?}"));
    }
    Ok(())
}

fn validate_tree_path(path: &str) -> Result<()> {
    validate_relative_path(path)?;
    if path.len() > 4096 {
        return fail(format!("tree path exceeds 4096 UTF-8 bytes: {path:?}"));
    }
    let components = path.split('/').collect::<Vec<_>>();
    if components.len() > 64 {
        return fail(format!("tree path exceeds 64 components: {path:?}"));
    }
    for component in components {
        if component.len() > 255 {
            return fail(format!("tree path component exceeds 255 bytes: {path:?}"));
        }
    }
    Ok(())
}

fn round_up_512(value: usize) -> Result<usize> {
    value
        .checked_add(padding_len(value))
        .ok_or_else(|| invalid_data("512-byte padding overflow"))
}

fn padding_len(value: usize) -> usize {
    let remainder = value % USTAR_BLOCK_BYTES;
    if remainder == 0 {
        0
    } else {
        USTAR_BLOCK_BYTES - remainder
    }
}

fn invalid_data(message: impl Into<String>) -> DynError {
    std::io::Error::new(std::io::ErrorKind::InvalidData, message.into()).into()
}

fn fail<T>(message: impl Into<String>) -> Result<T> {
    Err(invalid_data(message))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strict_archive_has_exact_terminator_and_malm_identity() {
        let mut tree = SourceTree::default();
        tree.insert("empty".to_owned(), TreeEntry::Directory)
            .unwrap();
        tree.insert(
            "nested/file.txt".to_owned(),
            TreeEntry::File(b"hello\n".to_vec()),
        )
        .unwrap();
        tree.insert("nested".to_owned(), TreeEntry::Directory)
            .unwrap();
        let archive = encode_strict_ustar(&tree, &BTreeSet::new()).unwrap();
        assert_eq!(&archive[archive.len() - 1024..], &[0_u8; 1024]);
        assert!(inspect_with_malm(&archive).is_ok());
        let parsed = parse_upstream_tar(&archive).unwrap();
        assert_eq!(parsed.entries.len(), 3);
    }

    #[test]
    fn ustar_path_split_preserves_long_utf8_path() {
        let prefix = "directory/".repeat(18);
        let path = format!("{prefix}file.svg");
        let (name, stored_prefix) = split_ustar_path(&path).unwrap();
        assert_eq!(format!("{stored_prefix}/{name}"), path);
        assert!(name.len() <= 100);
        assert!(stored_prefix.len() <= 155);
    }
}
