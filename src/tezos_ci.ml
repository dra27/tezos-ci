module Git = Current_git
module Docker = Current_docker.Default
module Analyse = Analyse
module Packaging = Packaging

let () = Logging.init ()

let monthly = Current_cache.Schedule.v ~valid_for:(Duration.of_day 30) ()

let obuilder_spec_build spec =
  let open Current.Syntax in
  let dockerfile =
    let _ = Bos.OS.Dir.create (Fpath.v "/tmp/tezos-ci") in
    let dockerfile =
      let+ spec = spec in
      Obuilder_spec.Docker.dockerfile_of_spec ~buildkit:true spec
    in
    let path =
      let+ dockerfile = dockerfile in
      let hash = Digest.string dockerfile |> Digest.to_hex in
      Fpath.v (Fmt.str "/tmp/tezos-ci/Dockerfile.%s.tez" hash)
    in
    let+ () = Current_fs.save path dockerfile and+ path = path in
    `File path
  in
  Docker.build ~pull:true ~dockerfile

let program_name = "tezos-ci"

let pipeline =
  let open Current.Syntax in
  let repo_tezos =
    Git.clone ~schedule:monthly "https://gitlab.com/tezos/tezos"
  in
  Current.all
    [
      Analyse.v repo_tezos |> Current.ignore_value;
      obuilder_spec_build (Current.return Build.v) (`Git repo_tezos)
      |> Current.ignore_value;
      obuilder_spec_build
        (Current.return Integration.integration_010_many_bakers)
        (`Git repo_tezos)
      |> Current.ignore_value;
    ]

let main current_config mode =
  let engine =
    Current.Engine.create ~config:current_config (fun () ->
        pipeline |> Current.ignore_value)
  in
  let site =
    let routes = Current_web.routes engine in
    Current_web.Site.(v ~has_role:allow_all) ~name:program_name routes
  in
  Logging.run
    (Lwt.choose
       [
         Current.Engine.thread engine;
         (* The main thread evaluating the pipeline. *)
         Current_web.run ~mode site;
         (* Optional: provides a web UI *)
       ])

(* Command-line parsing *)

open Cmdliner

let cmd =
  let doc = "an OCurrent pipeline" in
  ( Term.(const main $ Current.Config.cmdliner $ Current_web.cmdliner),
    Term.info program_name ~doc )

let () = Term.(exit @@ eval cmd)
