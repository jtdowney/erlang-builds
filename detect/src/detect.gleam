import argv
import gleam/bool
import gleam/dict.{type Dict}
import gleam/int
import gleam/io
import gleam/json.{type Json}
import gleam/list
import gleam/option.{type Option}
import gleam/order.{type Order}
import gleam/result
import gleam/set.{type Set}
import gleam/string
import simplifile
import tom

const usage = "usage:
  detect matrix <tags_file> <assets_file> [force]
  detect distributions"

pub type Distro {
  Distro(codename: String, image: String)
}

pub type Config {
  Config(otp_lines: List(String), arches: List(String), distros: List(Distro))
}

pub type BuildConfig {
  BuildConfig(
    otp: String,
    codename: String,
    image: String,
    arch: String,
    runner: String,
  )
}

pub type Outputs {
  Outputs(matrix: String, has_work: Bool)
}

pub type Package {
  Package(version: String, codename: String, arch: String)
}

fn fail(message: String) -> Nil {
  io.println_error(message)
  halt(1)
}

@external(erlang, "erlang", "halt")
fn halt(code: Int) -> Nil

pub fn main() -> Nil {
  case argv.load().arguments {
    ["matrix", tags_file, assets_file, ..rest] ->
      run_matrix(tags_file, assets_file, force_arg(rest))
    ["distributions"] -> run_distributions()
    _ -> io.println_error(usage)
  }
}

fn force_arg(rest: List(String)) -> String {
  case rest {
    [value, ..] -> value
    [] -> ""
  }
}

fn run_matrix(tags_file: String, assets_file: String, force: String) -> Nil {
  case build_matrix_outputs(tags_file, assets_file, force) {
    Ok(outputs) -> {
      let has_work = case outputs.has_work {
        True -> "true"
        False -> "false"
      }

      io.println("matrix=" <> outputs.matrix)
      io.println("has_work=" <> has_work)
    }
    Error(message) -> fail(message)
  }
}

fn build_matrix_outputs(
  tags_file: String,
  assets_file: String,
  force: String,
) -> Result(Outputs, String) {
  use tags <- result.try(read_file(tags_file))
  use assets <- result.try(read_file(assets_file))
  use config <- result.map(read_config())

  let tags =
    tags
    |> string.split("\n")
    |> list.map(string.trim)
    |> list.filter(fn(line) { !string.is_empty(line) })
  let assets =
    assets
    |> string.split("\n")
    |> list.map(string.trim)
    |> list.filter(fn(line) { !string.is_empty(line) })
  build_outputs(config, tags:, assets:, force:)
}

fn run_distributions() -> Nil {
  case read_config() {
    Ok(config) -> io.println(distributions(config))
    Error(message) -> fail(message)
  }
}

fn read_file(path: String) -> Result(String, String) {
  result.replace_error(simplifile.read(path), "detect: could not read " <> path)
}

fn read_config() -> Result(Config, String) {
  case simplifile.read("gleam.toml") {
    Ok(raw) ->
      result.replace_error(
        parse_config(raw),
        "detect: could not parse [tools.detect.targets] in gleam.toml",
      )
    Error(_) -> Error("detect: could not read gleam.toml")
  }
}

pub fn parse_config(toml_source: String) -> Result(Config, Nil) {
  use config <- result.try(result.replace_error(tom.parse(toml_source), Nil))
  let targets =
    tom.get_table(config, ["tools", "detect", "targets"])
    |> result.unwrap(dict.new())

  use otp_lines <- result.try(
    tom.get_array(targets, ["otp_lines"])
    |> result.try(list.try_map(_, tom.as_string))
    |> result.replace_error(Nil),
  )
  use arches <- result.try(
    tom.get_array(targets, ["arches"])
    |> result.try(list.try_map(_, tom.as_string))
    |> result.replace_error(Nil),
  )
  use distros <- result.try(
    tom.get_array(targets, ["distros"])
    |> result.try(list.try_map(_, toml_as_distro))
    |> result.replace_error(Nil),
  )
  Ok(Config(otp_lines:, arches:, distros:))
}

fn toml_as_distro(value: tom.Toml) -> Result(Distro, tom.GetError) {
  use fields <- result.try(tom.as_table(value))
  use codename <- result.try(tom.get_string(fields, ["codename"]))
  use image <- result.try(tom.get_string(fields, ["image"]))
  Ok(Distro(codename:, image:))
}

pub fn build_outputs(
  config: Config,
  tags tags: List(String),
  assets assets: List(String),
  force force: String,
) -> Outputs {
  let #(latest, existing) = case string.trim(force) {
    "" -> #(latest_versions(tags, config.otp_lines), existing_packages(assets))
    forced -> {
      let line = case string.split(forced, ".") {
        [line, ..] -> line
        _ -> forced
      }
      #(dict.from_list([#(line, forced)]), set.new())
    }
  }

  let combos =
    missing_matrix(
      latest,
      distros: config.distros,
      arches: config.arches,
      existing:,
    )
  let has_work = !list.is_empty(combos)
  Outputs(matrix: json.to_string(json.array(combos, combo_to_json)), has_work:)
}

fn combo_to_json(combo: BuildConfig) -> Json {
  json.object([
    #("otp", json.string(combo.otp)),
    #("codename", json.string(combo.codename)),
    #("image", json.string(combo.image)),
    #("arch", json.string(combo.arch)),
    #("runner", json.string(combo.runner)),
  ])
}

fn latest_versions(
  tags: List(String),
  major_versions: List(String),
) -> Dict(String, String) {
  major_versions
  |> list.filter_map(fn(major) {
    latest_per_major(tags, major)
    |> result.map(fn(version) { #(major, version) })
  })
  |> dict.from_list
}

pub fn latest_per_major(
  tags: List(String),
  major: String,
) -> Result(String, Nil) {
  list.fold(tags, option.None, fn(acc, tag) {
    case parse_version(tag) {
      Ok(#(line, version)) if line == major ->
        option.Some(keep_newer(acc, version))
      _ -> acc
    }
  })
  |> option.to_result(Nil)
}

fn keep_newer(current: Option(String), version: String) -> String {
  case current {
    option.None -> version
    option.Some(existing) ->
      case compare_version(version, existing) {
        order.Gt -> version
        _ -> existing
      }
  }
}

pub fn parse_version(tag: String) -> Result(#(String, String), Nil) {
  case tag {
    "OTP-" <> rest -> {
      use <- bool.guard(when: string.contains(rest, "-"), return: Error(Nil))
      let parts = string.split(rest, ".")
      use <- bool.guard(when: !valid_version_parts(parts), return: Error(Nil))

      case parts {
        [line, ..] -> Ok(#(line, rest))
        [] -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

fn valid_version_parts(parts: List(String)) -> Bool {
  list.length(parts) >= 2
  && list.all(parts, fn(part) { result.is_ok(int.parse(part)) })
}

pub fn compare_version(a: String, b: String) -> Order {
  compare_parts(version_ints(a), version_ints(b))
}

fn version_ints(version: String) -> List(Int) {
  version |> string.split(".") |> list.filter_map(int.parse)
}

fn compare_parts(a: List(Int), b: List(Int)) -> Order {
  case a, b {
    [], [] -> order.Eq
    [], _ -> order.Lt
    _, [] -> order.Gt
    [x, ..xs], [y, ..ys] ->
      case int.compare(x, y) {
        order.Eq -> compare_parts(xs, ys)
        other -> other
      }
  }
}

pub fn existing_packages(assets: List(String)) -> Set(Package) {
  list.fold(assets, set.new(), fn(acc, name) {
    case parse_asset(name) {
      Ok(key) -> set.insert(acc, key)
      Error(_) -> acc
    }
  })
}

pub fn parse_asset(name: String) -> Result(Package, Nil) {
  use <- bool.guard(when: !string.ends_with(name, ".deb"), return: Error(Nil))

  case string.split(string.drop_end(name, 4), "_") {
    [_package, middle, arch] -> {
      use <- bool.guard(
        when: arch != "amd64" && arch != "arm64",
        return: Error(Nil),
      )
      use #(version, release_codename) <- result.try(string.split_once(
        middle,
        "-",
      ))

      case string.split_once(release_codename, ".") {
        Ok(#(_release, codename)) -> Ok(Package(version:, codename:, arch:))
        Error(_) -> Error(Nil)
      }
    }
    _ -> Error(Nil)
  }
}

pub fn missing_matrix(
  latest: Dict(String, String),
  distros distros: List(Distro),
  arches arches: List(String),
  existing existing: Set(Package),
) -> List(BuildConfig) {
  let versions =
    latest
    |> dict.values
    |> list.sort(compare_version)
  list.flat_map(versions, fn(version) {
    list.flat_map(distros, fn(distro) {
      list.filter_map(arches, fn(arch) {
        case
          set.contains(
            existing,
            Package(version:, codename: distro.codename, arch:),
          )
        {
          True -> Error(Nil)
          False ->
            Ok(BuildConfig(
              otp: version,
              codename: distro.codename,
              image: distro.image,
              arch:,
              runner: runner_for(arch),
            ))
        }
      })
    })
  })
}

fn runner_for(arch: String) -> String {
  case arch {
    "arm64" -> "ubuntu-24.04-arm"
    _ -> "ubuntu-24.04"
  }
}

pub fn distributions(config: Config) -> String {
  let architectures = string.join(config.arches, " ")
  config.distros
  |> list.map(distribution_stanza(_, architectures))
  |> string.join("\n\n")
  |> string.append("\n")
}

fn distribution_stanza(distro: Distro, architectures: String) -> String {
  string.join(
    [
      "Origin: erlang-builds",
      "Label: erlang-builds",
      "Codename: " <> distro.codename,
      "Suite: " <> distro.codename,
      "Architectures: " <> architectures,
      "Components: main",
      "SignWith: yes",
      "Description: Erlang/OTP packages for " <> distro.codename,
    ],
    "\n",
  )
}
