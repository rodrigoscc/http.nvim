local Parser = require("http-nvim.parser").Parser

describe("Parse response", function()
    it("should fail parsing response", function()
        local parser = Parser.new()
        assert.has_error(function()
            parser:parse_response({ "No response" })
        end, "could not parse curl output, header size not found")
    end)

    it("should parse response status code", function()
        local parser = Parser.new()
        local response = parser:parse_response({
            "HTTP/1.0 200 OK",
            "Server: SimpleHTTP/0.6 Python/3.13.1",
            "Date: Fri, 14 Feb 2025 17:24:46 GMT",
            "Content-type: text/html",
            "Content-Length: 17",
            "Last-Modified: Fri, 14 Feb 2025 17:24:07 GMT",
            "",
            "<h1>Example</h1>",
            "",
            "0.001258",
            "185",
        })

        assert.are_equal(200, response.status_code)
    end)

    it("should parse response status line", function()
        local parser = Parser.new()
        local response = parser:parse_response({
            "HTTP/1.0 200 OK",
            "Server: SimpleHTTP/0.6 Python/3.13.1",
            "Date: Fri, 14 Feb 2025 17:24:46 GMT",
            "Content-type: text/html",
            "Content-Length: 17",
            "Last-Modified: Fri, 14 Feb 2025 17:24:07 GMT",
            "",
            "<h1>Example</h1>",
            "",
            "0.001258",
            "185",
        })

        assert.are_equal("HTTP/1.0 200 OK", response.status_line)
    end)

    it("should parse response ok", function()
        local parser = Parser.new()

        local response = parser:parse_response({
            "HTTP/1.0 200 OK",
            "Server: SimpleHTTP/0.6 Python/3.13.1",
            "Date: Fri, 14 Feb 2025 17:24:46 GMT",
            "Content-type: text/html",
            "Content-Length: 17",
            "Last-Modified: Fri, 14 Feb 2025 17:24:07 GMT",
            "",
            "<h1>Example</h1>",
            "",
            "0.001258",
            "185",
        })

        assert.are_equal(true, response.ok)

        response = parser:parse_response({
            "HTTP/1.0 400 Bad Request",
            "Server: SimpleHTTP/0.6 Python/3.13.1",
            "Date: Fri, 14 Feb 2025 17:24:46 GMT",
            "Content-type: text/html",
            "Content-Length: 17",
            "Last-Modified: Fri, 14 Feb 2025 17:24:07 GMT",
            "",
            "Error",
            "",
            "0.001258",
            "185",
        })

        assert.are_equal(false, response.ok)
    end)

    it("should parse response headers", function()
        local parser = Parser.new()

        local response = parser:parse_response({
            "HTTP/1.0 200 OK",
            "Server: SimpleHTTP/0.6 Python/3.13.1",
            "Date: Fri, 14 Feb 2025 17:24:46 GMT",
            "Content-type: text/html",
            "Content-Length: 17",
            "Last-Modified: Fri, 14 Feb 2025 17:24:07 GMT",
            "X-Custom: this one contains colons: after colon",
            "",
            "<h1>Example</h1>",
            "",
            "0.001258",
            "233",
        })

        assert.are_equal(
            "SimpleHTTP/0.6 Python/3.13.1",
            response.headers["Server"]
        )
        assert.are_equal(
            "Fri, 14 Feb 2025 17:24:46 GMT",
            response.headers["Date"]
        )
        assert.are_equal("text/html", response.headers["Content-type"])
        assert.are_equal(
            "Fri, 14 Feb 2025 17:24:07 GMT",
            response.headers["Last-Modified"]
        )
        assert.are_equal(
            "this one contains colons: after colon",
            response.headers["X-Custom"]
        )
    end)
end)
