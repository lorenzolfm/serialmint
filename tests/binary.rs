//! The binary, run as a person runs it.

#[test]
fn it_says_hello() {
    let output = std::process::Command::new(env!("CARGO_BIN_EXE_serialmint"))
        .output()
        .unwrap();

    assert!(output.status.success(), "{output:?}");
    assert_eq!(String::from_utf8(output.stdout).unwrap(), "Hello, world!\n");
}
