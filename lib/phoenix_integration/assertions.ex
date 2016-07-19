defmodule PhoenixIntegration.Assertions do

#  import IEx

  defmodule ResponseError do
    defexception [message: "#{IO.ANSI.red}The conn's response was not formed as expected\n"]
  end


  def assert_response(conn = %Plug.Conn{}, conditions) do
    Enum.each(conditions, fn({condition, value}) ->
      case condition do
        :body ->          assert_body(conn, value)
        :content_type ->  assert_content_type(conn, value)
        :status ->        assert_status(conn, value)
        :html ->          assert_body_html(conn, value)
        :json ->          assert_body_json( conn, value )
        :uri ->           assert_uri(conn, value)
        :path ->          assert_uri(conn, value, :path)
        :redirect ->      assert_redirect(conn, value)
        :to ->            assert_redirect(conn, value, :to)
      end
    end)
    conn
  end

  def refute_response(conn = %Plug.Conn{}, conditions) do
    Enum.each(conditions, fn({condition, value}) ->
      case condition do
        :body ->          refute_body(conn, value)
        :content_type ->  refute_content_type(conn, value)
        :status ->        refute_status(conn, value)
        :html ->          refute_body_html(conn, value)
        :json ->          refute_body_json( conn, value )
        :uri ->           refute_uri(conn, value)
        :path ->          refute_uri(conn, value, :path)
        :redirect ->      refute_redirect(conn, value)
        :to ->            refute_redirect(conn, value, :to)
      end
    end)
    conn
  end

  #----------------------------------------------------------------------------
  defp assert_uri(conn, expected, err_type \\ :uri) do
    # parse the expected uri
    uri = URI.parse expected

    # prepare the path and query data
    {uri_path, conn_path} = case uri.path do
      nil -> {nil, nil}
      _path -> {uri.path, conn.request_path}
    end
    {uri_query, conn_query} = case uri.query do
      nil -> {nil, nil}
      _query ->
        # decode the queries to get order independence
        {URI.decode_query( uri.query ), URI.decode_query( conn.query_string )}
    end

    # The main test
    pass = cond do
      uri_path && uri_query -> (uri_path == conn_path) && (uri_query == conn_query)
      uri_path -> uri_path == conn_path
      uri_query -> uri_query == conn_query
    end

    # raise or not as appropriate
    if pass do
      conn
    else
      # raise an appropriate error
      full_path = case conn.query_string do
        nil -> conn.request_path
        "" -> conn.request_path
        query -> conn.request_path <> "?" <> query
      end

      msg = error_msg_type( err_type ) <>
        error_msg_expected( expected ) <>
        error_msg_found( full_path )
      raise %ResponseError{ message: msg }
    end
  end

  #----------------------------------------------------------------------------
  defp refute_uri(conn, expected, err_type \\ :uri) do
    # parse the expected uri
    uri = URI.parse expected

    # prepare the path and query data
    {uri_path, conn_path} = case uri.path do
      nil -> {nil, nil}
      _path -> {uri.path, conn.request_path}
    end
    {uri_query, conn_query} = case uri.query do
      nil -> {nil, nil}
      _query ->
        # decode the queries to get order independence
        {URI.decode_query( uri.query ), URI.decode_query( conn.query_string )}
    end

    # The main test
    pass = cond do
      uri_path && uri_query -> (uri_path != conn_path) || (uri_query != conn_query)
      uri_path -> uri_path != conn_path
      uri_query -> uri_query != conn_query
    end

    # raise or not as appropriate
    if pass do
      conn
    else
      # raise an appropriate error
      full_path = case conn.query_string do
        nil -> conn.request_path
        "" -> conn.request_path
        query -> conn.request_path <> "?" <> query
      end

      msg = error_msg_type( err_type ) <>
        error_msg_expected( "path to NOT be:" <> full_path ) <>
        error_msg_found( full_path )
      raise %ResponseError{ message: msg }
    end
  end

  #----------------------------------------------------------------------------
  defp assert_redirect(conn, expected, err_type \\ :redirect) do
    assert_status( conn, 302 )
    case Plug.Conn.get_resp_header(conn, "location") do
      [^expected] -> conn
      [to] ->
        msg = error_msg_type( err_type ) <>
          error_msg_expected( to_string(expected) ) <>
          error_msg_found( to_string(to) )
        raise %ResponseError{ message: msg }
    end
  end

  #----------------------------------------------------------------------------
  defp refute_redirect(conn, expected, err_type \\ :redirect) do
    case conn.status do
      302 ->
        case Plug.Conn.get_resp_header(conn, "location") do
          [^expected] ->
            msg = error_msg_type( err_type ) <>
              error_msg_expected( "to NOT redirect to: " <> to_string(expected) ) <>
              error_msg_found( "redirect to: " <> to_string(expected) )
            raise %ResponseError{ message: msg }
          [_to] -> conn
        end
      _other -> conn
    end
  end

  #----------------------------------------------------------------------------
  defp assert_body_html(conn, expected, err_type \\ :html) do
    assert_content_type(conn, "text/html", err_type)
    |> assert_body( expected, err_type )
  end

  #----------------------------------------------------------------------------
  defp refute_body_html(conn, expected, err_type \\ :html) do
    # slightly different than asserting body_html
    # good if not html content
    case Plug.Conn.get_resp_header(conn, "content-type") do
      [] -> conn
      [header] ->
        cond do
          header =~ "text/html"->
            refute_body( conn, expected, err_type )
          true -> conn
        end
    end
  end

  #----------------------------------------------------------------------------
  defp assert_body_json(conn, expected, err_type \\ :json) do
    assert_content_type(conn, "application/json", err_type)
    case Poison.decode!( conn.resp_body ) do
      ^expected -> conn
      data ->
        msg = error_msg_type( err_type ) <>
          error_msg_expected( inspect(expected) ) <>
          error_msg_found( inspect(data) )
        raise %ResponseError{ message: msg }
    end
  end

  #----------------------------------------------------------------------------
  defp refute_body_json(conn, expected, err_type \\ :json) do
    # similar to refute body html, ok if content isn't json
    case Plug.Conn.get_resp_header(conn, "content-type") do
      [] -> conn
      [header] ->
        cond do
          header =~ "json"->
            case Poison.decode!( conn.resp_body ) do
              ^expected ->
                msg = error_msg_type( err_type ) <>
                  error_msg_expected( "to NOT find " <> inspect(expected) ) <>
                  error_msg_found( inspect(expected) )
                raise %ResponseError{ message: msg }
              _data -> conn
            end
          true -> conn
        end
    end
  end

  #----------------------------------------------------------------------------
  defp assert_body(conn, expected, err_type \\ :body) do
    if conn.resp_body =~ expected do
      conn
    else
      msg = error_msg_type( err_type ) <>
        error_msg_expected( "to find \"#{expected}\"" ) <>
        error_msg_found( "Not in the response body\n" ) <>
        IO.ANSI.yellow <>
        conn.resp_body
      raise %ResponseError{ message: msg }
    end
  end

  #----------------------------------------------------------------------------
  defp refute_body(conn, expected, err_type \\ :body) do
    if conn.resp_body =~ expected do
      msg = error_msg_type( err_type ) <>
        error_msg_expected( "NOT to find \"#{expected}\"" ) <>
        error_msg_found( "in the response body\n" ) <>
        IO.ANSI.yellow <>
        conn.resp_body
      raise %ResponseError{ message: msg }
    else
      conn
    end
  end

  #----------------------------------------------------------------------------
  defp assert_status(conn, status, err_type \\ :status) do
    case conn.status do
      ^status -> conn
      other ->
        msg = error_msg_type( err_type ) <>
          error_msg_expected( to_string(status) ) <>
          error_msg_found( to_string(other) )
        raise %ResponseError{ message: msg }
    end
  end

  #----------------------------------------------------------------------------
  defp refute_status(conn, status, err_type \\ :status) do
    case conn.status do
      ^status ->
        msg = error_msg_type( err_type ) <>
          error_msg_expected( "NOT " <> to_string(status) ) <>
          error_msg_found( to_string(status) )
        raise %ResponseError{ message: msg }
      _other -> conn
    end
  end

  #----------------------------------------------------------------------------
  defp assert_content_type(conn, expected_type, err_type \\ :content_type) do
    case Plug.Conn.get_resp_header(conn, "content-type") do
      [] -> 
        # no content type header was found
        msg = error_msg_type( err_type ) <>
          error_msg_expected("content-type header of \"#{expected_type}\"") <>
          error_msg_found( "No content-type header was found" )
        raise %ResponseError{ message: msg }
      [header] ->
        cond do
          header =~ expected_type->
            # success case
            conn
          true ->
            # there was a content type header, but the wrong one
            msg = error_msg_type( err_type ) <>
              error_msg_expected("content-type including \"#{expected_type}\"") <>
              error_msg_found( "\"#{header}\"" )
            raise %ResponseError{ message: msg }
        end
    end
  end

  #----------------------------------------------------------------------------
  defp refute_content_type(conn, expected_type, err_type \\ :content_type) do
    case Plug.Conn.get_resp_header(conn, "content-type") do
      [] -> conn
      [header] ->
        cond do
          header =~ expected_type->
            # the refuted content_type header was found
            msg = error_msg_type( err_type ) <>
              error_msg_expected("content-type to NOT be \"#{expected_type}\"") <>
              error_msg_found( "\"#{header}\"" )
            raise %ResponseError{ message: msg }
          true -> conn
        end
    end
  end

  #----------------------------------------------------------------------------
  defp error_msg_type(type) do
    "#{IO.ANSI.red}The conn's response was not formed as expected\n" <>
    "#{IO.ANSI.green}Error verifying #{IO.ANSI.cyan}:#{type}\n"
  end
  #----------------------------------------------------------------------------
  defp error_msg_expected(msg) do
    "#{IO.ANSI.green}Expected: #{IO.ANSI.red}#{msg}\n"
  end
  #----------------------------------------------------------------------------
  defp error_msg_found(msg) do
    "#{IO.ANSI.green}Found: #{IO.ANSI.red}#{msg}\n"
  end

end



































