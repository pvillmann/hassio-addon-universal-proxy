# Checks one catalog template and prints one line per problem (nothing = ok).
#
#   jq -r --arg id <file name without .json> -f validate.jq template.json
#
# The add-on runs this on every template before it uses it, CI runs it on every
# pull request. The rules keep templates to data that can only move paths: the
# apps run on the same origin as Home Assistant, so a template that could put
# arbitrary text into a page could also steal the Home Assistant login.

def top_keys: ["format", "id", "name", "revision", "min_addon", "tested_with",
  "homepage", "icon", "admin_only", "user_headers", "fields", "setup",
  "headers", "rewrite", "charset"];
def leads: ["\"", "'", "=", " ", "(", "\\", "\\u0027"];
def suffixes: ["/", "\\/", "?", "\"", "'"];

def check(cond; msg): if cond then empty else msg end;
def opt(f): . == null or f;
def text($max): type == "string" and length > 0 and length <= $max;
def only_keys($allowed): type == "object" and ((keys - $allowed) | length == 0);
def path_ok: type == "string" and test("^/[A-Za-z0-9._~/-]{1,100}$");
def header_name_ok:
  type == "string" and test("^[A-Za-z0-9-]{1,64}$")
  and (ascii_downcase
    | (IN("host", "connection", "upgrade", "x-real-ip", "x-ingress-path")
       or startswith("remote-") or startswith("x-forwarded-")
       or startswith("x-remote-user"))
    | not);
def header_value_ok: type == "string" and length <= 200 and test("^[^$\"\\\\;{}\r\n]*$");
# a rule may only put {base} (the ingress path) in front of a path
def rule_ok:
  only_keys(["from", "to"])
  and (.from | text(200)) and (.to | type == "string")
  and (.from | test("[$<>\r\n]|\\{base\\}") | not)
  and ((.to | split("{base}")) as $p
    | ($p | length) == 2 and ($p | add) == .from and ($p[1] | startswith("/")));

if type != "object" then "template must be a JSON object" else
  . as $t
  | ($t.rewrite // {}) as $r
  | check(only_keys(top_keys); "unknown keys: \((keys - top_keys) | join(", "))"),
    check(.format == 1; "format must be 1"),
    check(.id == $id; "id must be the file name (\($id))"),
    check(.id | type == "string" and test("^[a-z0-9][a-z0-9-]{0,39}$") and . != "custom";
      "id: lowercase letters, digits and -, not \"custom\""),
    check(.name | text(60); "name: text, up to 60 characters"),
    check(.revision | type == "number" and . >= 1 and . == floor; "revision: whole number from 1"),
    check(.min_addon | type == "string" and test("^[0-9]+\\.[0-9]+\\.[0-9]+$"); "min_addon: version like 0.6.0"),
    check(.tested_with | opt(text(100)); "tested_with: text, up to 100 characters"),
    check(.homepage | opt(text(200) and test("^https://[^\"'<>\\s]+$")); "homepage: https link"),
    check(.icon | opt(type == "string" and test("^mdi:[a-z0-9-]{1,60}$")); "icon: mdi:name"),
    check(.admin_only | opt(type == "boolean"); "admin_only: true or false"),
    check(.user_headers | opt(type == "boolean"); "user_headers: true or false"),
    check(.setup | opt(text(4000)); "setup: text, up to 4000 characters"),
    check(.fields | opt(only_keys(["url", "secret"])); "fields: only url and secret"),
    check(.fields.url | opt(only_keys(["example", "help"])
      and (.example | opt(text(200))) and (.help | opt(text(500)))); "fields.url: example, help"),
    check(.fields.secret | opt(only_keys(["required", "header", "help"])
      and (.header | header_name_ok) and (.required | opt(type == "boolean"))
      and (.help | opt(text(500)))); "fields.secret: header (allowed name), required, help"),
    check(.headers | opt(type == "object" and (to_entries
      | all(.[]; (.key | header_name_ok) and (.value | header_value_ok))));
      "headers: allowed names, values without $ \" \\ ; { }"),
    check($r | only_keys(["paths", "leads", "suffixes", "rules"]); "rewrite: paths, leads, suffixes, rules"),
    check($r.paths | opt(type == "array" and all(.[]; path_ok)); "rewrite.paths: paths like /api"),
    check($r.leads | opt(type == "array" and all(.[]; IN(leads[]))); "rewrite.leads: only \(leads | tojson)"),
    check($r.suffixes | opt(type == "array" and all(.[]; IN(suffixes[]))); "rewrite.suffixes: only \(suffixes | tojson)"),
    check($r.rules | opt(type == "array" and all(.[]; rule_ok));
      "rewrite.rules: \"to\" must be \"from\" with {base} put once in front of a /"),
    check((($r.paths // []) | length) * (($r.leads // [0, 0]) | length) * (($r.suffixes // [0]) | length)
      + (($r.rules // []) | length) <= 500; "rewrite: more than 500 rules"),
    check(.charset | opt(only_keys(["source", "skip"])
      and .source == "iso-8859-1" and (.skip | opt(path_ok))); "charset: source iso-8859-1, skip a path")
end
