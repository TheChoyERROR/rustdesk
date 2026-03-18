use std::{
    collections::HashMap,
    path::Path,
    sync::Mutex,
    time::{SystemTime, UNIX_EPOCH},
};

use chrono::{SecondsFormat, Utc};
use hbb_common::{
    config::{keys, Config, LocalConfig},
    sodiumoxide::base64::{self, Variant},
    log, tokio, whoami,
};
use serde_json::{json, Value};
use uuid::Uuid;

const MONITORING_URL_ENV: &str = "RUSTDESK_MONITORING_URL";
const MONITORING_URL_OPTION: &str = "monitoring-server-url";
const MONITORING_URL_OPTION_LEGACY: &str = "monitoring-server";
const MONITORING_DISPLAY_NAME_OPTION: &str = "monitoring-display-name";
const MONITORING_AVATAR_URL_ENV: &str = "RUSTDESK_MONITORING_AVATAR_URL";
const MONITORING_AVATAR_URL_OPTION: &str = "monitoring-avatar-url";
const MONITORING_AVATAR_PATH_OPTION: &str = "monitoring-avatar-path";
const USER_INFO_OPTION: &str = "user_info";
const MAX_LOCAL_AVATAR_BYTES: u64 = 2 * 1024 * 1024;

const EVENT_SESSION_STARTED: &str = "session_started";
const EVENT_SESSION_ENDED: &str = "session_ended";
const EVENT_PARTICIPANT_JOINED: &str = "participant_joined";
const EVENT_PARTICIPANT_LEFT: &str = "participant_left";
const EVENT_CONTROL_CHANGED: &str = "control_changed";
const EVENT_PARTICIPANT_ACTIVITY: &str = "participant_activity";

lazy_static::lazy_static! {
    static ref LAST_ACTIVITY_EMIT_MS: Mutex<HashMap<String, u64>> = Default::default();
}

#[derive(Clone, Copy)]
pub enum MonitoringDirection {
    Incoming,
    Outgoing,
}

impl MonitoringDirection {
    fn as_str(self) -> &'static str {
        match self {
            Self::Incoming => "incoming",
            Self::Outgoing => "outgoing",
        }
    }
}

pub fn emit_session_started(
    session_id: String,
    user_id: String,
    direction: MonitoringDirection,
    meta: Option<Value>,
) {
    emit_event(EVENT_SESSION_STARTED, session_id, user_id, direction, meta);
}

pub fn emit_session_ended(
    session_id: String,
    user_id: String,
    direction: MonitoringDirection,
    meta: Option<Value>,
) {
    emit_event(EVENT_SESSION_ENDED, session_id, user_id, direction, meta);
}

pub fn emit_participant_joined(
    session_id: String,
    user_id: String,
    direction: MonitoringDirection,
    meta: Option<Value>,
) {
    emit_event(
        EVENT_PARTICIPANT_JOINED,
        session_id,
        user_id,
        direction,
        meta,
    );
}

pub fn emit_participant_left(
    session_id: String,
    user_id: String,
    direction: MonitoringDirection,
    meta: Option<Value>,
) {
    emit_event(EVENT_PARTICIPANT_LEFT, session_id, user_id, direction, meta);
}

pub fn emit_control_changed(
    session_id: String,
    user_id: String,
    direction: MonitoringDirection,
    meta: Option<Value>,
) {
    emit_event(EVENT_CONTROL_CHANGED, session_id, user_id, direction, meta);
}

pub fn emit_participant_activity_throttled(
    session_id: String,
    user_id: String,
    direction: MonitoringDirection,
    signal: &'static str,
    interval_ms: u64,
) {
    if session_id.trim().is_empty() {
        return;
    }

    let key = format!("{}:{}:{}", session_id, user_id, direction.as_str());
    let now_ms = unix_millis_now();

    let should_emit = {
        let mut lock = LAST_ACTIVITY_EMIT_MS
            .lock()
            .expect("activity throttle lock poisoned");
        if let Some(last_ms) = lock.get(&key) {
            if now_ms.saturating_sub(*last_ms) < interval_ms {
                false
            } else {
                lock.insert(key, now_ms);
                true
            }
        } else {
            lock.insert(key, now_ms);
            true
        }
    };

    if !should_emit {
        return;
    }

    emit_event(
        EVENT_PARTICIPANT_ACTIVITY,
        session_id,
        user_id,
        direction,
        Some(json!({ "activity_signal": signal })),
    );
}

pub fn participant_meta(
    participant_id: &str,
    display_name: Option<&str>,
    avatar_url: Option<&str>,
) -> Value {
    json!({
        "participant_id": participant_id,
        "display_name": display_name,
        "avatar_url": avatar_url,
    })
}

pub fn participant_control_meta(
    participant_id: &str,
    display_name: Option<&str>,
    avatar_url: Option<&str>,
    is_control_active: bool,
) -> Value {
    let mut meta = participant_meta(participant_id, display_name, avatar_url);
    if let Some(object) = meta.as_object_mut() {
        object.insert(
            "is_control_active".to_owned(),
            Value::Bool(is_control_active),
        );
    }
    meta
}

pub fn local_user_id() -> String {
    let id = Config::get_id().trim().to_owned();
    if id.is_empty() {
        whoami::username()
    } else {
        id
    }
}

pub fn local_display_name(fallback_user_id: &str) -> String {
    let monitoring_display_name = local_option_or_global_option(MONITORING_DISPLAY_NAME_OPTION);
    let monitoring_display_name = monitoring_display_name.trim();
    if !monitoring_display_name.is_empty() {
        return monitoring_display_name.to_owned();
    }

    let built_in_display_name = crate::ui_interface::get_builtin_option(keys::OPTION_DISPLAY_NAME);
    let built_in_display_name = built_in_display_name.trim();
    if !built_in_display_name.is_empty() {
        return built_in_display_name.to_owned();
    }

    let alias = Config::get_option("alias").trim().to_owned();
    if !alias.is_empty() {
        return alias;
    }

    if let Some(info) = local_user_info() {
        if let Some(name) = json_trimmed_string(&info, "display_name")
            .or_else(|| json_trimmed_string(&info, "name"))
        {
            return name;
        }
    }

    let username = crate::username();
    let username = username.trim();
    if !username.is_empty() {
        return username.to_owned();
    }

    fallback_user_id.trim().to_owned()
}

pub fn local_avatar_url() -> Option<String> {
    let env_value = std::env::var(MONITORING_AVATAR_URL_ENV).unwrap_or_default();
    if let Some(avatar) = resolve_avatar_candidate(&env_value) {
        return Some(avatar);
    }

    let option_value = local_option_or_global_option(MONITORING_AVATAR_URL_OPTION);
    if let Some(avatar) = resolve_avatar_candidate(&option_value) {
        return Some(avatar);
    }

    let local_path_value = local_option_or_global_option(MONITORING_AVATAR_PATH_OPTION);
    if let Some(avatar) = avatar_data_url_from_path(local_path_value.trim()) {
        return Some(avatar);
    }

    if let Some(info) = local_user_info() {
        if let Some(avatar) = json_trimmed_string(&info, "avatar_url")
            .or_else(|| json_trimmed_string(&info, "avatar"))
            .or_else(|| json_trimmed_string(&info, "image"))
            .and_then(|value| resolve_avatar_candidate(&value))
        {
            return Some(avatar);
        }

        if let Some(path) = json_trimmed_string(&info, "avatar_local_path") {
            if let Some(avatar) = avatar_data_url_from_path(path.trim()) {
                return Some(avatar);
            }
        }
    }

    None
}

fn local_option_or_global_option(key: &str) -> String {
    let local = LocalConfig::get_option(key);
    if !local.trim().is_empty() {
        return local;
    }
    Config::get_option(key)
}

pub fn local_participant_meta(participant_id: &str) -> Value {
    let display_name = local_display_name(participant_id);
    let avatar_url = local_avatar_url();
    participant_meta(
        participant_id,
        Some(display_name.as_str()),
        avatar_url.as_deref(),
    )
}

pub fn local_control_meta(participant_id: &str, is_control_active: bool) -> Value {
    let display_name = local_display_name(participant_id);
    let avatar_url = local_avatar_url();
    participant_control_meta(
        participant_id,
        Some(display_name.as_str()),
        avatar_url.as_deref(),
        is_control_active,
    )
}

fn emit_event(
    event_type: &'static str,
    session_id: String,
    user_id: String,
    direction: MonitoringDirection,
    meta: Option<Value>,
) {
    if session_id.trim().is_empty() {
        return;
    }
    let Some(endpoint) = monitoring_endpoint() else {
        return;
    };

    let payload = json!({
        "event_id": Uuid::new_v4().to_string(),
        "event_type": event_type,
        "session_id": session_id,
        "user_id": user_id,
        "direction": direction.as_str(),
        "timestamp": Utc::now().to_rfc3339_opts(SecondsFormat::Millis, true),
        "host_info": {
            "hostname": whoami::hostname(),
            "os": std::env::consts::OS,
            "app_version": env!("CARGO_PKG_VERSION"),
        },
        "meta": meta.unwrap_or_else(|| json!({})),
    });

    let body = match serde_json::to_string(&payload) {
        Ok(body) => body,
        Err(err) => {
            log::warn!("failed to serialize monitoring event payload: {}", err);
            return;
        }
    };

    std::thread::spawn(move || {
        post_monitoring_event(endpoint, body);
    });
}

fn monitoring_endpoint() -> Option<String> {
    let env_url = std::env::var(MONITORING_URL_ENV).unwrap_or_default();
    let mut url = env_url.trim().to_owned();

    if url.is_empty() {
        url = Config::get_option(MONITORING_URL_OPTION).trim().to_owned();
    }
    if url.is_empty() {
        url = Config::get_option(MONITORING_URL_OPTION_LEGACY)
            .trim()
            .to_owned();
    }
    if url.is_empty() {
        return None;
    }

    let endpoint = if url.ends_with("/api/v1/session-events") {
        url
    } else {
        format!("{}/api/v1/session-events", url.trim_end_matches('/'))
    };

    Some(endpoint)
}

fn local_user_info() -> Option<Value> {
    serde_json::from_str::<Value>(&LocalConfig::get_option(USER_INFO_OPTION))
        .ok()
        .filter(|value| value.is_object())
}

fn json_trimmed_string(value: &Value, key: &str) -> Option<String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(str::trim)
        .filter(|v| !v.is_empty())
        .map(|v| v.to_owned())
}

fn resolve_avatar_candidate(raw: &str) -> Option<String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }

    if trimmed.starts_with("http://")
        || trimmed.starts_with("https://")
        || trimmed.starts_with("data:image/")
    {
        return Some(trimmed.to_owned());
    }

    avatar_data_url_from_path(trimmed)
}

fn avatar_data_url_from_path(raw_path: &str) -> Option<String> {
    let mut path = raw_path.trim();
    if path.is_empty() {
        return None;
    }
    if let Some(rest) = path.strip_prefix("file://") {
        path = rest;
    }

    let path_ref = Path::new(path);
    if !path_ref.exists() {
        return None;
    }

    let mime = match path_ref
        .extension()
        .and_then(|ext| ext.to_str())
        .map(|ext| ext.to_ascii_lowercase())
        .as_deref()
    {
        Some("jpg") | Some("jpeg") => "image/jpeg",
        Some("png") => "image/png",
        Some("webp") => "image/webp",
        _ => {
            log::warn!("unsupported local avatar image extension: {}", path);
            return None;
        }
    };

    let metadata = match std::fs::metadata(path_ref) {
        Ok(meta) => meta,
        Err(err) => {
            log::warn!(
                "failed to read metadata for local avatar image '{}': {}",
                path,
                err
            );
            return None;
        }
    };

    if metadata.len() > MAX_LOCAL_AVATAR_BYTES {
        log::warn!(
            "local avatar image '{}' too large ({} bytes > {} bytes)",
            path,
            metadata.len(),
            MAX_LOCAL_AVATAR_BYTES
        );
        return None;
    }

    let bytes = match std::fs::read(path_ref) {
        Ok(bytes) => bytes,
        Err(err) => {
            log::warn!("failed to read local avatar image '{}': {}", path, err);
            return None;
        }
    };

    if bytes.is_empty() {
        return None;
    }

    let encoded = base64::encode(bytes, Variant::Original);
    Some(format!("data:{mime};base64,{encoded}"))
}

#[tokio::main(flavor = "current_thread")]
async fn post_monitoring_event(endpoint: String, body: String) {
    if let Err(err) = crate::post_request(endpoint.clone(), body, "").await {
        log::debug!("failed to send monitoring event to {}: {}", endpoint, err);
    }
}

fn unix_millis_now() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_millis() as u64)
        .unwrap_or(0)
}
