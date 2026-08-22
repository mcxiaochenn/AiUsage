//! Credential boundary.
//!
//! This module intentionally contains no persistence implementation. Flutter
//! owns platform keystores via `flutter_secure_storage`; Rust receives a
//! `SecureCredential` only for the duration of an FFI call and may return a
//! rotated bundle for Flutter to store atomically. SQLite stores only quota
//! metadata in `history`.

pub const CREDENTIAL_BOUNDARY: &str = "flutter_secure_storage";
