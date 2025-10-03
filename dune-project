(lang dune 3.12)
(name heycaml)
(generate_opam_files true)

(package
 (name heycaml)
 (synopsis "Simple OCaml REST API practice app")
 (description "RESTful API with configuration and logging")
 (depends
  (ocaml (>= 4.14.0))
  dune
  opium
  yojson))
