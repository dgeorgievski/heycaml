open Opium

(* Configuration types *)
type config = {
  name : string;
  port : int;
}

type config_overrides = {
  name : string option;
  port : int option;
}

let default_config : config = { name = "heycaml"; port = 8080 }

let config_overrides_empty : config_overrides = { name = None; port = None }

let merge_config (base : config) (overrides : config_overrides) : config =
  let name = Option.value overrides.name ~default:base.name in
  let port = Option.value overrides.port ~default:base.port in
  { name; port }

let partial_from_json json : config_overrides =
  let open Yojson.Safe.Util in
  let name = json |> member "name" |> to_string_option in
  let port = json |> member "port" |> to_int_option in
  { name; port }

let overrides_from_json path : (config_overrides, string) result =
  match Yojson.Safe.from_file path with
  | json -> Ok (partial_from_json json)
  | exception Yojson.Json_error msg ->
      Error (Printf.sprintf "JSON parse error: %s" msg)
  | exception Sys_error msg -> Error msg

let strip_quotes value =
  let len = String.length value in
  if len >= 2 then
    match (value.[0], value.[len - 1]) with
    | ('"', '"') | ('\'', '\'') -> String.sub value 1 (len - 2)
    | _ -> value
  else value

let parse_yaml_line overrides line =
  let trimmed = String.trim line in
  if trimmed = "" || trimmed.[0] = '#' then Ok overrides
  else
    match String.index_opt trimmed ':' with
    | None -> Ok overrides
    | Some idx ->
        let key = String.sub trimmed 0 idx |> String.trim |> String.lowercase_ascii in
        let raw_value =
          String.sub trimmed (idx + 1) (String.length trimmed - idx - 1)
          |> String.trim
          |> strip_quotes
        in
        match key with
        | "name" -> Ok { overrides with name = Some raw_value }
        | "port" -> (
            match int_of_string_opt raw_value with
            | Some p -> Ok { overrides with port = Some p }
            | None -> Error (Printf.sprintf "Invalid port value in YAML: %s" raw_value))
        | _ -> Ok overrides

let overrides_from_yaml path : (config_overrides, string) result =
  try
    let channel = open_in path in
    let rec loop overrides =
      match input_line channel with
      | line -> (
          match parse_yaml_line overrides line with
          | Ok updated -> loop updated
          | Error _ as err ->
              close_in_noerr channel;
              err )
      | exception End_of_file ->
          close_in channel;
          Ok overrides
    in
    loop config_overrides_empty
  with Sys_error msg -> Error msg

let overrides_from_file path : (config_overrides, string) result =
  match String.lowercase_ascii (Filename.extension path) with
  | ".json" -> overrides_from_json path
  | ".yaml" | ".yml" -> overrides_from_yaml path
  | ext -> Error (Printf.sprintf "Unsupported configuration file extension: %s" ext)

let parse_args () : string option * config_overrides =
  let config_path = ref None in
  let name_override = ref None in
  let port_override = ref None in
  let speclist =
    [
      ( "-config"
      , Arg.String (fun s -> config_path := Some s)
      , "Path to configuration file (JSON or YAML)" );
      ( "-name"
      , Arg.String (fun s -> name_override := Some s)
      , "Override application name" );
      ( "-port"
      , Arg.Int (fun p -> port_override := Some p)
      , "Override port (defaults to 8080)" );
    ]
  in
  let usage =
    "Usage: heycaml [-config path] [-name app_name] [-port port_number]"
  in
  Arg.parse speclist (fun _ -> ()) usage;
  (!config_path, { name = !name_override; port = !port_override })

let build_config () : config =
  let file_path_opt, cli_overrides = parse_args () in
  let file_overrides_result =
    match file_path_opt with
    | None -> Ok config_overrides_empty
    | Some path -> overrides_from_file path
  in
  match file_overrides_result with
  | Ok file_overrides ->
      let with_file = merge_config default_config file_overrides in
      let combined = merge_config with_file cli_overrides in
      if combined.port <= 0 || combined.port > 65_535 then (
        prerr_endline "Port must be between 1 and 65535";
        exit 1 )
      else
      combined
  | Error msg ->
      prerr_endline msg;
      exit 1

let iso8601_timestamp () =
  let open Unix in
  let tm = gmtime (time ()) in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ" (tm.tm_year + 1900) (tm.tm_mon + 1)
    tm.tm_mday tm.tm_hour tm.tm_min tm.tm_sec

let request_logger =
  let filter handler request =
    let open Lwt.Syntax in
    let* response = handler request in
    let timestamp = iso8601_timestamp () in
    let method_ =
      request.Opium.Request.meth |> Opium.Method.to_string |> String.uppercase_ascii
    in
    let path = request.Opium.Request.target in
    let status = Response.status response |> Opium.Status.to_code in
    Printf.printf "%s %s %s -> %d\n%!" timestamp method_ path status;
    Lwt.return response
  in
  Rock.Middleware.create ~name:"request-logger" ~filter

let version_handler (config : config) _req =
  let body =
    `Assoc
      [
        ("name", `String config.name);
        ("version", `String "1.0.0");
      ]
  in
  Response.of_json body |> Lwt.return

let health_handler (config : config) _req =
  let body = `Assoc [ (config.name, `String "OK") ] in
  Response.of_json body |> Lwt.return

let build_app (config : config) =
  App.empty
  |> App.middleware request_logger
  |> App.get "/version" (version_handler config)
  |> App.get "/healthz" (health_handler config)
  |> App.get "/heatlhz" (health_handler config)
  |> App.port config.port

let () =
  let config = build_config () in
  Printf.printf "Starting %s on port %d\n%!" config.name config.port;
  let app = build_app config in
  let forever, _resolver = Lwt.wait () in
  let open Lwt.Syntax in
  Lwt_main.run
    (let* _server = App.start app in
     forever)
