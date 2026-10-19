// Local log of incoming sessions (who connected, when, for how long), written by the
// connection manager. The CM runs in the logged-in user's context, so the main window,
// which runs as the same user, can read the file back.

use hbb_common::{config::Config, log};
use serde_derive::{Deserialize, Serialize};
use std::{
    collections::HashMap,
    fs::{self, OpenOptions},
    io::Write,
    path::PathBuf,
    sync::Mutex,
    time::{SystemTime, UNIX_EPOCH},
};

const FILE_NAME: &str = "conn_log.jsonl";
const MAX_ENTRIES: usize = 1000;

#[derive(Serialize, Deserialize)]
struct Entry {
    peer_id: String,
    name: String,
    start: i64,
    end: i64,
}

struct Pending {
    peer_id: String,
    name: String,
    added: i64,
    authorized: Option<i64>,
}

lazy_static::lazy_static! {
    static ref PENDING: Mutex<HashMap<i32, Pending>> = Default::default();
}

fn now() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or(0)
}

fn path() -> PathBuf {
    Config::path(FILE_NAME)
}

pub fn on_add(conn_id: i32, peer_id: &str, name: &str, authorized: bool) {
    let t = now();
    let mut pending = PENDING.lock().unwrap();
    let p = pending.entry(conn_id).or_insert_with(|| Pending {
        peer_id: peer_id.to_owned(),
        name: name.to_owned(),
        added: t,
        authorized: None,
    });
    if authorized && p.authorized.is_none() {
        p.authorized = Some(t);
    }
}

pub fn on_authorized(conn_id: i32) {
    if let Some(p) = PENDING.lock().unwrap().get_mut(&conn_id) {
        if p.authorized.is_none() {
            p.authorized = Some(now());
        }
    }
}

// `was_authorized` covers accept paths that never call `on_authorized`, e.g. elevation.
pub fn on_remove(conn_id: i32, was_authorized: bool) {
    let Some(p) = PENDING.lock().unwrap().remove(&conn_id) else {
        return;
    };
    let start = match (p.authorized, was_authorized) {
        (Some(t), _) => t,
        (None, true) => p.added,
        (None, false) => return,
    };
    let entry = Entry {
        peer_id: p.peer_id,
        name: p.name,
        start,
        end: now(),
    };
    if let Err(e) = append(&entry) {
        log::error!("failed to write connection log: {}", e);
    }
}

fn append(entry: &Entry) -> std::io::Result<()> {
    let path = path();
    let text = fs::read_to_string(&path).unwrap_or_default();
    let lines: Vec<&str> = text.lines().collect();
    if lines.len() >= MAX_ENTRIES {
        let keep = lines[lines.len() + 1 - MAX_ENTRIES..].join("\n");
        fs::write(&path, keep + "\n")?;
    }
    let mut f = OpenOptions::new().create(true).append(true).open(&path)?;
    let line = serde_json::to_string(entry).map_err(|e| std::io::Error::new(std::io::ErrorKind::Other, e))?;
    writeln!(f, "{}", line)
}

/// Newest first, as a JSON array.
pub fn get_json() -> String {
    let text = fs::read_to_string(path()).unwrap_or_default();
    let entries: Vec<Entry> = text
        .lines()
        .rev()
        .filter_map(|l| serde_json::from_str(l).ok())
        .take(MAX_ENTRIES)
        .collect();
    serde_json::to_string(&entries).unwrap_or_else(|_| "[]".to_owned())
}

pub fn clear() {
    if let Err(e) = fs::remove_file(path()) {
        if e.kind() != std::io::ErrorKind::NotFound {
            log::error!("failed to clear connection log: {}", e);
        }
    }
}
