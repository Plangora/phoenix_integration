defmodule PhoenixIntegration.Requests do
  use Phoenix.ConnTest
  
  @endpoint Application.get_env(:phoenix_integration, :endpoint)

  #----------------------------------------------------------------------------
  @doc """
  Given a conn who's response is a redirect, it calls the path indicated by the 
  redirect "location" response header and returns the conn from that call.

  This will recursively follow up to _max_redirects_ redirect responses.
  """
  def follow_redirect(conn = %Plug.Conn{}, max_redirects \\ 5) do
    if max_redirects == 0 do
      raise "Too Many Redirects"
    end
    case conn.status do
      302 ->
        # we want to use the returned conn for the redirects as it
        # contains state that might be needed
        [location] = Plug.Conn.get_resp_header(conn, "location")
        get(conn, location)
        |> follow_redirect(max_redirects - 1)
      _ -> conn
    end
  end

  #----------------------------------------------------------------------------
  @doc """
  Similar to a standard get/post/put/patch/delete call in a ConnTest except that follow_path
  follows any redirects returned in the conn's response header.

  ## Options
    * `:method` - method use when requesting the path. Defaults to `"get"`;
    * `:max_redirects` - Maximum number of redirects to follow. defaults to `5`;
  """
  def follow_path(conn, path, opts \\ %{} )
  def follow_path(conn = %Plug.Conn{}, path, opts ) when is_list(opts) do
    follow_path(conn, path, Enum.into(opts, %{}) )
  end
  def follow_path(conn = %Plug.Conn{}, path, opts ) do
    opts = Map.merge(%{
      method: "get",
      max_redirects: 5
      }, opts)

    request_path(conn, path, opts.method)
    |> follow_redirect( opts.max_redirects )
  end

  #----------------------------------------------------------------------------
  @doc """
  Finds a link in conn.resp_body, requests it as if the user had clicked on it,
  and returns the resulting conn.

  `click_link` does not follow any redirects returned by the request. This allows
  you to explicitly check that the redirect is correct. Use `follow_redirect` to request
  the location redirected to, or just use `follow_link` to do it in one call.

  For example:
      get( conn, thing_path(conn, :index) )
      |> click_link( "something that redirects to new" )
      |> assert_response( status: 302, to: think_path(conn, :new) )
      |> follow_redirect()
      |> assert_response( status: 200, path: think_path(conn, :new) )

  If the link is not found in the body, `click_link` raises an error.

  Any redirects are __not__ followed.

  ### Parameters
  `conn` should be a conn returned from a previous request that rendered some html. The
  functions are designed to pass the conn from one call into the next via pipes.

  `identifier` indicates which link to find in the html. Valid values can be in the following
  forms:
    * `"/some/path"` specify the link's href starting with a `"/"` character
    * `"http://www.example.com/some/uri"`, specify the href as full uri starting with either `"http"` or `"https"`
    * `"#element-id"` specify the html element id of the link you are looking for. Must start
      start with the `"#"` character (same as css id specifier).
    * `"Some Text"` specify text contained within the link you are looking for.

  Examples:

      # click a link specified by path or uri
      get( conn, thing_path(conn, :index) )
      |> click_link( page_path(conn, :index) )

      # click a link specified by html id
      get( conn, thing_path(conn, :index) )
      |> click_link( "#link-id" )

      # click a link containing the given text
      get( conn, thing_path(conn, :index) )
      |> click_link( conn, "Settings" )

  ### Options
    * `:method` - link method to look for in the html. Defaults to `"get"`;


  ### Links that don't use the :get method

  When Phoneix.Html renders a link, it usually generates an `<a>` tag. However, if you 
  specify a method other than :get, then it generates a form that looks like a link.

      <%= link "Delete Thing", to: thing_path(conn, :delete, thing), method: :delete %>

  If you did this, then specifiy the method to look for as an option.

      click_link( conn, thing_path(conn, :delete), method: :delete )
  """
  def click_link(conn, identifer, opts \\ %{})
  def click_link(conn = %Plug.Conn{}, path, opts ) when is_list(opts) do
    click_link(conn, path, Enum.into(opts, %{}) )
  end
  def click_link(conn = %Plug.Conn{}, identifer, opts) do
    opts = Map.merge( %{method: "get"}, opts )

    {:ok, href} = find_html_link(conn.resp_body, identifer, opts.method)
    request_path(conn, href, opts.method)
  end

  #----------------------------------------------------------------------------
  @doc """
  Finds a link in conn.resp_body, requests it as if the user had clicked on it,
  follows any redirects, and returns the resulting conn.

  This is similar to `click_link`, except that it follows returned redirects. This
  is very useful during integration tests as you typically want to emulate what the
  user is really doing. You should typically use follow_link more than click_link.

  For example:
      get( conn, thing_path(conn, :index) )
      |> follow_link( "something that redirects to new" )
      |> assert_response( status: 200, path: think_path(conn, :new) )
      |> follow_link( "Cancel" )
      |> assert_response( status: 200, path: think_path(conn, :index) )


  If the link is not found in the body, `click_link` raises an error.


  ### Parameters
  `conn` should be a conn returned from a previous request that rendered some html. The
  functions are designed to pass the conn from one call into the next via pipes.

  `identifier` indicates which link to find in the html. Valid values can be in the following
  forms:
    * `"/some/path"` specify the link's href starting with a `"/"` character
    * `"http://www.example.com/some/uri"`, specify the href as full uri starting with either `"http"` or `"https"`
    * `"#element-id"` specify the html element id of the link you are looking for. Must start
      start with the `"#"` character (same as css id specifier).
    * `"Some Text"` specify text contained within the link you are looking for.

  Example:

      # click through several pages that should point to each other
      get( conn, thing_path(conn, :index) )
      |> follow_link( conn, "#settings" )
      |> follow_link( conn, "Cancel" )
      |> assert_response( path: thing_path(conn, :index) )

  ### Options
    * `:method` - link method to look for in the html. Defaults to `"get"`;
    * `:max_redirects` - Maximum number of redirects to follow. defaults to `5`;

  ### Links that don't use the :get method

  When Phoneix.Html renders a link, it usually generates an `<a>` tag. However, if you 
  specify a method other than :get, like this:

      <%= link "Delete Thing", to: thing_path(conn, :delete, thing), method: :delete %>

  Then Phoenix generates html looks like a link, but is really a form using the method.
  This is why you must specify the method used in `opts` if you used anything other
  than the standard :get in your link.

  For example:

      # follow a non-get link
      follow_link( conn, thing_path(conn, :delete), method: :delete )
  """
  def follow_link(conn, indentifer, opts \\ %{} )
  def follow_link(conn = %Plug.Conn{}, indentifer, opts ) when is_list(opts) do
    follow_link(conn, indentifer, Enum.into(opts, %{}) )
  end
  def follow_link(conn = %Plug.Conn{}, indentifer, opts ) do
    opts = Map.merge(%{
      method: "get",
      max_redirects: 5
      }, opts)

    click_link(conn, indentifer, opts)
    |> follow_redirect( opts.max_redirects )
  end

  #----------------------------------------------------------------------------
  @doc """
  Finds a form in the conn's resp_body html, fills out the fields with the given
  data, and requests the form's action with the given data.

  You can identify which form to find by specifying the action (starting with either a "/" or
  "http"), the form's id (starting with a "#", or textual content in the form)

  If the link is not in the body, it raises an error.

  Any redirects are __not__ followed.

  ## Options
    * `:identifier` - /action, #id or text to identify the form. Defaults to `nil`;
    * `:method` - restricts the forms searched to those whose action uses the given
      method (such as "post" or "put"). Defaults to `nil`;
    * `:finder` - finding string passed to `Floki.find`. Defaults to `"form"`
  """
  def submit_form(conn, fields, opts \\ %{} )
  def submit_form(conn = %Plug.Conn{}, fields, opts ) when is_list(opts) do
    submit_form(conn, fields, Enum.into(opts, %{}) )
  end
  def submit_form(conn = %Plug.Conn{}, fields, opts ) do
    opts = Map.merge( %{
        identifier: nil,
        method: nil,
        finder: "form"
      }, opts )

    # find the form
    {:ok, form_action, form_method, form} =
      find_html_form(conn.resp_body, opts.identifier, opts.method, opts.finder)

    # build the data to send to the action pointed to by the form
    form_data = build_form_data(form, fields)

    # use ConnCase to call the form's handler. return the new conn
    request_path(conn, form_action, form_method, form_data )
  end

  #----------------------------------------------------------------------------
  @doc """
  Similar to submit_form, except that it does follow redirects.

  ## Options
    * `:identifier` - /action, #id or text to identify the form. Defaults to `nil`;
    * `:method` - restricts the forms searched to those whose action uses the given
      method (such as "post" or "put"). Defaults to `nil`;
    * `:max_redirects` - Maximum number of redirects to follow. defaults to `5`;
  """
  def follow_form(conn, fields, opts \\ %{})
  def follow_form(conn = %Plug.Conn{}, fields, opts ) when is_list(opts) do
    follow_form(conn, fields, Enum.into(opts, %{}) )
  end
  def follow_form(conn = %Plug.Conn{}, fields, opts) do
    opts = Map.merge( %{max_redirects: 5}, opts)

    submit_form(conn, fields, opts)
    |> follow_redirect( opts.max_redirects )
  end

  #============================================================================
  #============================================================================
  # private below

  #----------------------------------------------------------------------------
  defp request_path(conn, path, method, data \\ %{} ) do
    case to_string(method) do
      "get" ->
        get( conn, path, data )
      "post" ->
        post( conn, path, data )
      "put" -> 
        put( conn, path, data )
      "patch" -> 
        patch( conn, path, data )
      "delete" ->
        delete( conn, path, data )
    end
  end
  #----------------------------------------------------------------------------
  # don't really care if there are multiple copies of the same link,
  # jsut that it is actually on the page
  defp find_html_link( html, identifier, :get ), do: find_html_link( html, identifier, "get" )
  defp find_html_link( html, identifier, "get" ) do
    identifier = String.strip(identifier)

    # scan all links, return the first where either the path or the content
    # is equal to the identifier
    Floki.find(html, "a")
    |> Enum.find_value( fn(link) ->
      {"a", _attribs, kids} = link

      case identifier do
        "#" <> id ->
          case Floki.attribute(link, "id") do
            [^id] -> link
            _ -> nil
          end
        "/" <> _ ->
          case Floki.attribute(link, "href") do
            [^identifier] -> link
            _ -> nil
          end
        "http" <> _ ->
          case Floki.attribute(link, "href") do
            [^identifier] -> link
            _ -> nil
          end
        _ ->
          cond do
            # see if the identifier is in the links's text
            Floki.text(kids) =~ identifier -> link
            # all other cases fail
            true -> nil 
          end
      end
    end)
    |> case do
      nil ->
        {err_type, err_ident} = case identifier do
          "#" <> id ->    {"id=", id}
          "/" <> _ ->     {"href=", identifier}
          "http" <> _ ->  {"href=", identifier}
          _ ->            {"text containing ", identifier}
        end
        msg = "Failed to find link \"#{identifier}\", :get in the response\n" <>
          "Expected to find an anchor with #{err_type}\"#{err_ident}\""
        raise msg
      link ->
        [path] = Floki.attribute(link, "href")
        {:ok, path}
    end
  end
  defp find_html_link( html, identifier, method ) do
    {:ok, path, _method, _form} =
      find_html_form(html, identifier, method, "form")
    {:ok, path}
  end

  #----------------------------------------------------------------------------
  defp find_html_form( html, identifier, method, form_finder ) do
    method = case method do
      nil -> nil
      other -> to_string(other)
    end

    # scan all links, return the first where either the path or the content
    # is equal to the identifier
    Floki.find(html, form_finder)
    |> Enum.find_value( fn(form) ->
      {"form", _attribs, _kids} = form
 
      case identifier do
        nil -> form         # if nil identifier, return the first form
        "#" <> id ->
          case Floki.attribute(form, "id") do
            [^id] -> form
            _ -> nil
          end
        "/" <> _ ->
          case Floki.attribute(form, "action") do
            [^identifier] -> form
            _ -> nil
          end
        "http" <> _ ->
          case Floki.attribute(form, "action") do
            [^identifier] -> form
            _ -> nil
          end
        _ ->
          cond do
            # see if the identifier is in the links's text
            Floki.text(form) =~ identifier -> form
            # all other cases fail
            true -> nil
          end
      end
      |> verify_form_method(method)
    end)
    |> case do
      nil ->
        {err_type, err_ident} = case identifier do
          "#" <> id ->    {"id=", id}
          "/" <> _ ->     {"action=", identifier}
          "http" <> _ ->  {"action=", identifier}
          _ ->            {"text containing ", identifier}
        end
        msg = "Failed to find form \"#{identifier}\", :#{method} in the response\n" <>
          "Expected to find a form with #{err_type}\"#{err_ident}\""
        raise msg
      form ->
        [path] = Floki.attribute(form, "action")
        {:ok, path, form_method(form), form}
    end
  end

  #----------------------------------------------------------------------------
  defp build_form_data(form, fields) do
    form_data = build_form_by_type(form, %{}, "input")
    form_data = build_form_by_type(form, form_data, "textarea")
    form_data = build_form_by_type(form, form_data, "select")

    # merge the data from the form and that provided by the test
    merge_grouped_fields( form_data, fields )
  end

  #========================================================
  # support for find

  #--------------------------------------------------------
  defp verify_form_method(false, _method),  do: false
  defp verify_form_method(nil, _method),    do: false
  defp verify_form_method(form, nil), do: form            # return form f no method requested
  defp verify_form_method(form, method) do
    method = to_string(method)
    form_method(form)
    |> case do
      ^method -> form
      _ -> false
    end
  end

  #--------------------------------------------------------
  defp form_method(form) do
        case Floki.find( form, "input[name=\"_method\"]" ) do
      [] ->
        "post"
      [found_input] ->
        [found_method] = Floki.attribute(found_input, "value")
        found_method
    end
  end


  #========================================================
  # support for building form data

  #----------------------------------------------------------------------------
  defp build_form_by_type(form, acc, input_type) do
    Enum.reduce(Floki.find(form, input_type), acc, fn(input, acc) ->
      case input_to_key_value(input, input_type) do
        {:ok, key, value} ->
          cond do
            is_map(value) ->
              # merge group named inputs together
              Map.put(acc, key, Map.merge( acc[key] || %{}, value))
            true ->
              Map.put(acc, key, value)
          end
        {:error, _} ->
          acc # do nothing
      end
    end )
  end

  #----------------------------------------------------------------------------'
  defp input_to_key_value(input, input_type) do
    case Floki.attribute(input, "type") do
      ["radio"] ->
        case Floki.attribute(input, "checked") do
          ["checked"] ->
            really_input_to_key_value(input, input_type)
          _ ->
            {:error, "skip"}
        end
      _ -> really_input_to_key_value(input, input_type)
    end
  end
  defp really_input_to_key_value(input, input_type) do
    case Floki.attribute(input, "name") do
      [] ->     {:error, :no_name}
      [name] -> interpret_named_value(name, get_input_value(input, input_type))
      _ ->      {:error, :unknown_format}
    end
  end

  #----------------------------------------------------------------------------
  defp merge_grouped_fields(map, fields) do
    Enum.reduce(fields, map, fn({k,v}, acc) ->
      cond do
        is_map(v) ->
          sub_map = merge_grouped_fields( acc[k] || %{}, v )
          put_if_available!(acc, k, sub_map)
        true ->
          put_if_available!(acc, k, v)
      end
    end)
  end

  #----------------------------------------------------------------------------
  defp put_if_available!(map, key, value) do
    case Map.has_key?(map, key) do
      true ->   Map.put(map, key, value)
      false ->
        msg = "#{IO.ANSI.red}Attempted to set missing input in form\n" <>
          "#{IO.ANSI.green}Setting key: #{IO.ANSI.red}#{key}\n" <>
          "#{IO.ANSI.green}And value: #{IO.ANSI.red}#{value}\n" <>
          "#{IO.ANSI.green}Into fields: #{IO.ANSI.yellow}" <>
          inspect( map )
        raise msg
    end
  end

  #----------------------------------------------------------------------------
  defp get_input_value( input, "input" ),     do: Floki.attribute(input, "value")
  defp get_input_value( input, "textarea" ),  do: [Floki.text(input)]
  defp get_input_value( input, "select" ) do
    Floki.find(input, "option[selected]")
    |> Floki.attribute("value")
  end

  #----------------------------------------------------------------------------'
  defp interpret_named_value(name, value) do
    case value do
      [] ->       build_named_value(name, nil)
      [value] ->  build_named_value(name, value)
      _ ->        {:error, :unknown_format}
    end
  end

  #----------------------------------------------------------------------------'
  defp build_named_value(name, value) do
    case Regex.scan(~r/\w+[\w+]/, name) do
      [[key]] ->            {:ok, String.to_atom(key), value}
      [[key], [sub_key]] -> {:ok, String.to_atom(key), %{String.to_atom(sub_key) => value}}
      _ ->                  {:error, :unknown_format}
    end
  end

end