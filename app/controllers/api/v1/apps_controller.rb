# frozen_string_literal: true

class Api::V1::AppsController < Api::BaseController
  skip_before_action :require_authenticated_user!

  def create
    options = application_options

    return forbidden if OAuthApplicationNameBlocklist.blocked?(options[:name])
    return forbidden if OAuthApplicationFingerprintBlocklist.blocked?(
      redirect_uris: options[:redirect_uri],
      website: options[:website],
      scopes: options[:scopes],
      confidential: true
    )

    @app = Doorkeeper::Application.create!(options)
    render json: @app, serializer: REST::CredentialApplicationSerializer
  end

  private

  def application_options
    {
      name: app_params[:client_name],
      redirect_uri: app_params[:redirect_uris],
      scopes: app_scopes_or_default,
      website: app_params[:website],
    }
  end

  def app_scopes_or_default
    app_params[:scopes] || Doorkeeper.configuration.default_scopes
  end

  def app_params
    params.permit(:client_name, :scopes, :website, :redirect_uris, redirect_uris: [])
  end
end
