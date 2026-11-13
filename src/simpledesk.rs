//! SimpleDesk: the client is set up once for one server, from its domain or IP address.

use base::config::keys;
use hbb_common::{
    config::{self, LocalConfig, PeerConfig},
    log,
};
use std::{io::Read, time::Duration};

/// Where a SimpleDesk server answers `{"key", "name", "version"}`, under `https://<address>`.
const SERVER_INFO_PATH: &str = "/api/simpledesk/server-info";
const SERVER_INFO_TIMEOUT: Duration = Duration::from_secs(10);
const SERVER_INFO_MAX_LEN: u64 = 64 * 1024;

/// Why a server could not be set up. The setup screen shows a text for each code.
#[derive(Debug, PartialEq)]
pub enum SetupError {
    Invalid,
    NotAllowed,
    Unreachable,
    NotSimpleDesk,
}

impl SetupError {
    pub fn code(&self) -> &'static str {
        match self {
            SetupError::Invalid => "invalid",
            SetupError::NotAllowed => "not-allowed",
            SetupError::Unreachable => "unreachable",
            SetupError::NotSimpleDesk => "not-simpledesk",
        }
    }
}

/// Whether a server is set up. Until then the UI shows the setup screen.
pub fn is_server_set_up() -> bool {
    !crate::ui_interface::get_option(keys::OPTION_CUSTOM_RENDEZVOUS_SERVER).is_empty()
}

/// Asks the server at `address` for its key and sets the client up for it: ID server, relay
/// and API server are all that address, over WebSocket on port 443.
pub fn set_up_server(address: &str) -> Result<(), SetupError> {
    let host = normalize_address(address).ok_or(SetupError::Invalid)?;
    if !hbb_common::simpledesk::is_server_allowed(&host) {
        return Err(SetupError::NotAllowed);
    }
    let key = fetch_server_key(&host)?;
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    let mut options = crate::ipc::get_options();
    #[cfg(any(target_os = "android", target_os = "ios"))]
    let mut options = hbb_common::config::Config::get_options();
    for (k, v) in [
        (keys::OPTION_CUSTOM_RENDEZVOUS_SERVER, host.clone()),
        (keys::OPTION_RELAY_SERVER, host.clone()),
        (keys::OPTION_API_SERVER, format!("https://{host}")),
        (keys::OPTION_KEY, key),
        (keys::OPTION_ALLOW_WEBSOCKET, "Y".to_owned()),
    ] {
        options.insert(k.to_owned(), v);
    }
    crate::ui_interface::set_options(options);
    #[cfg(target_os = "android")]
    crate::rendezvous_mediator::RendezvousMediator::restart();
    #[cfg(any(target_os = "android", target_os = "ios"))]
    crate::common::test_rendezvous_server();
    log::info!("Set up for the SimpleDesk server {host}");
    Ok(())
}

/// Clears what ties the client to its server, so it can be set up for another one: the server
/// settings with key and proxy, the login, the cached address books and devices, and the
/// permanent password. The device ID stays, so the IT still finds the device.
pub fn reset_client() {
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    let mut options = crate::ipc::get_options();
    #[cfg(any(target_os = "android", target_os = "ios"))]
    let mut options = config::Config::get_options();
    for k in [
        keys::OPTION_CUSTOM_RENDEZVOUS_SERVER,
        keys::OPTION_RELAY_SERVER,
        keys::OPTION_API_SERVER,
        keys::OPTION_KEY,
    ] {
        options.remove(k);
    }
    crate::ui_interface::set_options(options);
    crate::ui_interface::set_socks(String::new(), String::new(), String::new());
    if !crate::ui_interface::set_permanent_password_with_result(String::new()) {
        log::warn!("The permanent password was not cleared");
    }
    for k in ["access_token", "user_info"] {
        LocalConfig::set_option(k.to_owned(), String::new());
    }
    config::Ab::remove();
    config::Group::remove();
    for (id, _, _) in PeerConfig::get_vec_id_modified_time_path(&None) {
        PeerConfig::remove(&id);
    }
    LocalConfig::set_fav(Vec::new());
    let no_peers: Vec<config::DiscoveryPeer> = Vec::new();
    config::LanPeers::store(&no_peers);
    #[cfg(target_os = "android")]
    crate::rendezvous_mediator::RendezvousMediator::restart();
    log::info!("Client reset, the server has to be set up again");
}

/// The host in `address` as typed: without spaces, scheme, trailing slash or dot, in lower
/// case. `None` unless it is a domain or an IPv4 address; a port or path is not accepted.
fn normalize_address(address: &str) -> Option<String> {
    let address = address.trim().to_lowercase();
    let address = ["https://", "http://"]
        .iter()
        .find_map(|scheme| address.strip_prefix(scheme))
        .unwrap_or(&address);
    let host = address.trim_end_matches('/').trim_end_matches('.');
    if host.is_empty() || host.len() > 253 {
        return None;
    }
    if host.parse::<std::net::Ipv4Addr>().is_ok() {
        return Some(host.to_owned());
    }
    let is_label = |label: &str| {
        !label.is_empty()
            && label.len() <= 63
            && !label.starts_with('-')
            && !label.ends_with('-')
            && label.chars().all(|c| c.is_ascii_alphanumeric() || c == '-')
    };
    let looks_like_ip = host.chars().all(|c| c.is_ascii_digit() || c == '.');
    if !looks_like_ip && host.split('.').all(is_label) {
        Some(host.to_owned())
    } else {
        None
    }
}

fn fetch_server_key(host: &str) -> Result<String, SetupError> {
    let url = format!("https://{host}{SERVER_INFO_PATH}");
    let client = crate::hbbs_http::create_http_client_with_url_strict(&url).map_err(|e| {
        log::warn!("No HTTP client for {url}: {e}");
        SetupError::Unreachable
    })?;
    let resp = client
        .get(&url)
        .timeout(SERVER_INFO_TIMEOUT)
        .send()
        .map_err(|e| {
            log::warn!("{url} not reachable: {e}");
            SetupError::Unreachable
        })?;
    let status = resp.status();
    if !status.is_success() {
        log::warn!("{url} answered {status}");
        // A proxy in front of a server that is down answers 502 or 503.
        return Err(if status.is_server_error() {
            SetupError::Unreachable
        } else {
            SetupError::NotSimpleDesk
        });
    }
    let mut body = String::new();
    if let Err(e) = resp.take(SERVER_INFO_MAX_LEN).read_to_string(&mut body) {
        log::warn!("Failed to read the answer of {url}: {e}");
        return Err(SetupError::NotSimpleDesk);
    }
    key_from_server_info(&body).ok_or_else(|| {
        log::warn!("{url} gave no SimpleDesk server key");
        SetupError::NotSimpleDesk
    })
}

/// The public key of the server from its server info, if it is a valid key.
fn key_from_server_info(body: &str) -> Option<String> {
    let info: serde_json::Value = serde_json::from_str(body).ok()?;
    let key = info.get("key")?.as_str()?.trim();
    crate::common::get_rs_pk(key).map(|_| key.to_owned())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn takes_a_domain_or_ipv4_address() {
        for (typed, host) in [
            ("remote.example.de", "remote.example.de"),
            ("  Remote.Example.DE  ", "remote.example.de"),
            ("https://remote.example.de/", "remote.example.de"),
            ("remote.example.de.", "remote.example.de"),
            ("192.168.1.10", "192.168.1.10"),
        ] {
            assert_eq!(normalize_address(typed).as_deref(), Some(host), "{typed}");
        }
        for typed in [
            "",
            "remote.example.de:21116",
            "remote.example.de/ws",
            "user@remote.example.de",
            "remote..example.de",
            "-remote.example.de",
            "1.2.3",
            "999.1.1.1",
            "::1",
            "bad host",
        ] {
            assert_eq!(normalize_address(typed), None, "{typed}");
        }
    }

    #[test]
    fn reads_the_key_from_server_info() {
        let key = "kyaC2jNyp5a9Sz2q0D5VG0Ii3ca4xhChn0g5O2aOzyI=";
        let body = format!(r#"{{"key": "{key}", "name": "SimpleDesk", "version": "1.0"}}"#);
        assert_eq!(key_from_server_info(&body).as_deref(), Some(key));
        for body in [
            "",
            "<html>Welcome to nginx</html>",
            r#"{"name": "SimpleDesk"}"#,
            r#"{"key": "not a key"}"#,
            r#"{"key": 42}"#,
        ] {
            assert_eq!(key_from_server_info(body), None, "{body}");
        }
    }

    #[test]
    fn refuses_servers_that_are_not_allowed() {
        use hbb_common::config::Config;

        let evil = "evil.example";
        if hbb_common::simpledesk::is_server_allowed(evil) {
            // Built with SIMPLEDESK_ALLOWED_SERVERS empty: every server is allowed.
            return;
        }
        assert_eq!(set_up_server(evil), Err(SetupError::NotAllowed));
        Config::set_option(keys::OPTION_CUSTOM_RENDEZVOUS_SERVER.to_owned(), evil.to_owned());
        Config::set_option(keys::OPTION_RELAY_SERVER.to_owned(), format!("{evil}:21117"));
        assert!(!Config::get_rendezvous_server().contains(evil));
        assert!(!Config::get_option(keys::OPTION_RELAY_SERVER).contains(evil));
        assert_eq!(
            crate::common::get_api_server(format!("https://{evil}"), String::new()),
            ""
        );
    }
}
