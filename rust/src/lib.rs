//! Native domain core. Flutter reaches this crate only through the generated
//! flutter_rust_bridge boundary; OpenAI wire responses never cross the FFI.

pub mod api;
pub mod auth;
pub mod bridge;
pub mod history;
pub mod models;
pub mod normalize;
pub mod storage;

mod frb_generated;
