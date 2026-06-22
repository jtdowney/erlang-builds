import birdie
import detect
import gleam/dict
import gleam/order
import gleam/set
import gleeunit
import simplifile

pub fn main() {
  gleeunit.main()
}

pub fn latest_per_line_picks_highest_stable_patch_test() {
  let tags = [
    "OTP-27.3.2", "OTP-28.0", "OTP-28.0.1", "OTP-28.1", "OTP-29.0-rc1", "maint",
  ]

  assert detect.latest_per_major(tags, "28") == Ok("28.1")
  assert detect.latest_per_major(tags, "29") == Error(Nil)
}

pub fn compare_version_orders_numerically_test() {
  assert detect.compare_version("28.1", "28.0.1") == order.Gt
  assert detect.compare_version("28.1.5", "28.1") == order.Gt
  assert detect.compare_version("28.0", "28.0") == order.Eq
}

pub fn existing_combos_parses_asset_names_test() {
  let names = [
    "erlang_28.1-1.bookworm_amd64.deb",
    "erlang-wx_28.1-1.bookworm_amd64.deb",
    "erlang_28.1-1.noble_arm64.deb",
    "erlang_28.1-1.bookworm_i386.deb",
    "not-a-package.txt",
  ]
  let combos = detect.existing_packages(names)

  assert set.size(combos) == 2
  assert set.contains(
    combos,
    detect.Package(version: "28.1", codename: "bookworm", arch: "amd64"),
  )
  assert set.contains(
    combos,
    detect.Package(version: "28.1", codename: "noble", arch: "arm64"),
  )
}

pub fn missing_matrix_skips_built_combos_test() {
  let latest = dict.from_list([#("28", "28.1")])
  let distros = [detect.Distro(codename: "bookworm", image: "debian:bookworm")]
  let existing =
    set.from_list([
      detect.Package(version: "28.1", codename: "bookworm", arch: "amd64"),
    ])

  assert detect.missing_matrix(
      latest,
      distros:,
      arches: ["amd64", "arm64"],
      existing:,
    )
    == [
      detect.BuildConfig(
        otp: "28.1",
        codename: "bookworm",
        image: "debian:bookworm",
        arch: "arm64",
        runner: "ubuntu-24.04-arm",
      ),
    ]
}

pub fn forced_version_matrix_json_test() {
  let config =
    detect.Config(otp_lines: ["28", "29"], arches: ["amd64"], distros: [
      detect.Distro(codename: "bookworm", image: "debian:bookworm"),
    ])
  let outputs =
    detect.build_outputs(config, tags: [], assets: [], force: "28.1")

  assert outputs.has_work
  birdie.snap(outputs.matrix, title: "forced version build matrix json")
}

pub fn autodetect_matrix_json_test() {
  let config =
    detect.Config(otp_lines: ["28", "29"], arches: ["amd64", "arm64"], distros: [
      detect.Distro(codename: "bookworm", image: "debian:bookworm"),
      detect.Distro(codename: "noble", image: "ubuntu:24.04"),
    ])
  let tags = ["OTP-27.3", "OTP-28.1", "OTP-29.0", "OTP-29.0-rc1"]
  let assets = ["erlang_28.1-1.bookworm_amd64.deb"]
  let outputs = detect.build_outputs(config, tags:, assets:, force: "")

  birdie.snap(outputs.matrix, title: "autodetect build matrix json")
}

pub fn parse_config_reads_targets_table_test() {
  let assert Ok(toml) = simplifile.read("test/fixtures/targets.toml")

  assert detect.parse_config(toml)
    == Ok(
      detect.Config(
        otp_lines: ["28", "29"],
        arches: ["amd64", "arm64"],
        distros: [
          detect.Distro(codename: "bookworm", image: "debian:bookworm"),
          detect.Distro(codename: "noble", image: "ubuntu:24.04"),
        ],
      ),
    )
}

pub fn distributions_conf_test() {
  let config =
    detect.Config(otp_lines: ["28"], arches: ["amd64", "arm64"], distros: [
      detect.Distro(codename: "bookworm", image: "debian:bookworm"),
      detect.Distro(codename: "noble", image: "ubuntu:24.04"),
    ])

  birdie.snap(
    detect.distributions(config),
    title: "reprepro distributions conf",
  )
}
