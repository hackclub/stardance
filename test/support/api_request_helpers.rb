module ApiRequestHelpers
  def api_headers(user)
    { "Authorization" => "Bearer #{user.api_key}" }
  end

  def json_response
    JSON.parse(response.body)
  end
end
