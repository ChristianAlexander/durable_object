# Used by "mix format"
spark_locals_without_parens = [
  field: 2,
  field: 3,
  handler: 1,
  handler: 2,
  hibernate_after: 1,
  shutdown_after: 1
]

[
  import_deps: [:spark],
  plugins: [Spark.Formatter],
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  locals_without_parens: spark_locals_without_parens,
  export: [
    locals_without_parens: spark_locals_without_parens
  ]
]
