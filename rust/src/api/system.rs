/// Small Phase 1 health check. It deliberately has no network or storage side
/// effects and verifies the generated Rust-to-Dart binding on every platform.
pub fn ping() -> String {
    "pong from Rust".to_owned()
}

#[cfg(test)]
mod tests {
    use super::ping;

    #[test]
    fn answers_with_pong() {
        assert_eq!(ping(), "pong from Rust");
    }
}
