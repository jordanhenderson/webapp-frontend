--CREATE_DATABASE defines a query that can be used when webapp boots. Use to (re-) init database schema.
@def CREATE_DATABASE ""

@def WEBAPP_PARAM_BASEPATH 0
@def WEBAPP_PARAM_DBPATH 1
@def DATABASE_TYPE_SQLITE 0
@def DATABASE_TYPE_MYSQL 1
@def RESPONSE_TYPE_DATA 0
@def RESPONSE_TYPE_MESSAGE 1
@def _MESSAGE(msg, reload) '{"data":[{"msg":"' .. msg .. '"' .. (reload and ', "reload":1' or '') .. '}], "type":' .. RESPONSE_TYPE_MESSAGE .. '}'
@def MESSAGE(msg) _MESSAGE(msg, nil)
@def END_HEADER "\r\n"
@def HTML_HEADER "Content-type: text/html" .. END_HEADER
@def HTML_200 "HTTP/1.1 200 OK" .. END_HEADER
@def HTML_404 "HTTP/1.1 404 Not Found" .. END_HEADER
@def JSON_HEADER "Content-type: application/json" .. END_HEADER
@def CONTENT_LEN_HEADER(len) "Content-Length: " .. len .. END_HEADER
@def DATABASE_QUERY_INIT 0
@def DATABASE_QUERY_STARTED 1
@def DATABASE_QUERY_FINISHED 2
