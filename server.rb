# coding: utf-8
require 'sinatra'
require 'logger'
require 'json'
require 'openssl'
require 'octokit'
require 'jwt'
require 'time' # To get the ISO 8601 representation of a Time object

set :port, 3000

#
#
# This is a boilerplate server for your own GitHub App. You can read
# more about GitHub Apps here: https://developer.github.com/apps/
#
# On its own, this app does absolutely nothing, except that it can be
# installed.  It's up to you to add fun functionality!  You can check
# out one example in advanced_server.rb.
#
# This code is a Sinatra app, for two reasons.  First, because the app
# will require a landing page for installation.  Second, in
# anticipation that you will want to receive events over a webhook
# from GitHub, and respond to those in some way. Of course, not all
# apps need to receive and process events! Feel free to rip out the
# event handling code if you don't need it.
#
# Have fun! Please reach out to us if you have any questions, or just
# to show off what you've built!
#

class GHAapp < Sinatra::Application

  # Never, ever, hardcode app tokens or other secrets in your code!
  # Always extract from a runtime source, like an environment
  # variable.

  # Notice that the private key must be in PEM format, but the
  # newlines should be stripped and replaced with the literal
  # `\n`. This can be done in the terminal as such: export
  # GITHUB_PRIVATE_KEY=`awk '{printf "%s\\n", $0}' private-key.pem`
  PRIVATE_KEY = OpenSSL::PKey::RSA.new(ENV['GITHUB_PRIVATE_KEY']
                                         .gsub('\n', "\n")) # convert newlines

  # You set the webhook secret when you create your app. This verifies
  # that the webhook is really coming from GH.
  WEBHOOK_SECRET = ENV['GITHUB_WEBHOOK_SECRET']

  # Get the app identifier-an integer-from your app page after you
  # create your app. This isn't actually a secret, but it is something
  # easier to configure at runtime.
  APP_IDENTIFIER = ENV['GITHUB_APP_IDENTIFIER']

  ########## Configure Sinatra
  #
  # Let's turn on verbose logging during development
  #
  configure :development do
    set :logging, Logger::DEBUG
  end

  ########## Before each request to our app
  #
  # Before each request to our app, we want to instantiate an Octokit
  # client. Doing so requires that we construct a JWT.
  # https://jwt.io/introduction/ We have to also sign that JWT with
  # our private key, so GitHub can be sure that a) it came from us b)
  # it hasn't been altered by a malicious third party
  #
  before do
    payload = {
      # The time that this JWT was issued, _i.e._ now.
      iat: Time.now.to_i,

      # How long is the JWT good for (in seconds)?  Let's say it can
      # be used for 10 minutes before it needs to be refreshed.
      #
      # TODO we don't actually cache this token, we regenerate a new
      # one every time!
      exp: Time.now.to_i + (10 * 60),

      # Your GitHub App's identifier number, so GitHub knows who
      # issued the JWT, and know what permissions this token has.
      iss: APP_IDENTIFIER
    }

    # Cryptographically sign the JWT
    jwt = JWT.encode(payload, PRIVATE_KEY, 'RS256')

    # Create the Octokit client, using the JWT as the auth token.
    # Notice that this client will _not_ have sufficient permissions
    # to do many interesting things!  We might, for particular
    # endpoints, need to generate an installation token (using the
    # JWT), and instantiate a new client object. But we'll cross that
    # bridge when/if we get there!
    @client ||= Octokit::Client.new(bearer_token: jwt)
  end

  ########## Events
  #
  # This is the webhook endpoint that GH will call with events, and
  # hence where we will do our event handling
  #

  post '/' do
    request.body.rewind
    # We need the raw text of the body to check the webhook signature
    payload_raw = request.body.read
    begin
      payload = JSON.parse payload_raw
    rescue
      payload = {}
    end

    # Check X-Hub-Signature to confirm that this webhook was generated
    # by GitHub, and not a malicious third party.  The way this works
    # is: We have registered with GitHub a secret, and we have stored
    # it locally in WEBHOOK_SECRET.  GitHub will cryptographically
    # sign the request payload with this secret. We will do the same,
    # and if the results match, then we know that the request is from
    # GitHub (or, at least, from someone who knows the secret!)  If
    # they don't match, this request is an attack, and we should
    # reject it.  The signature comes in with header x-hub-signature,
    # and looks like "sha1=123456" We should take the left hand side
    # as the signature method, and the right hand side as the HMAC
    # digest (the signature) itself.
    their_signature_header = request.env['HTTP_X_HUB_SIGNATURE'] || 'sha1='
    method, their_digest = their_signature_header.split('=')
    our_digest = OpenSSL::HMAC.hexdigest(method, WEBHOOK_SECRET, payload_raw)
    halt 401 unless their_digest == our_digest

    # Determine what kind of event this is, and take action as
    # appropriate TODO we assume that GitHub will always provide an
    # X-GITHUB-EVENT header in this case, which is a reasonable
    # assumption, however we should probably be more careful!
    logger.debug "---- received event #{request.env['HTTP_X_GITHUB_EVENT']}"
    logger.debug "----         action #{payload['action']}" unless payload['action'].nil?

    case request.env['HTTP_X_GITHUB_EVENT']
    when 'issues'
      # Add code here to handle the event that you care about!
      handle_issue(payload)
    when 'issue_comment'
      handle_issue_comment(payload)
    when 'pull_request'
      handle_pull_request(payload)
    else
      logger.debug payload
    end

    'ok' # we have to return _something_ ;)
  end

  ########## Helpers
  #
  # These functions are going to help us do some tasks that we don't
  # want clogging up the happy paths above, or that need to be done
  # repeatedly. You can add anything you like here, really!
  #

  helpers do
    # This is our handler for the event that you care about! Of
    # course, you'll want to change the name to reflect the actual
    # event name! But this is where you will add code to process the
    # event.
    def handle_issue(payload)
      case payload['action']
      when 'opened'
        logger.debug 'Issue opened!'
        true
      else
        logger.debug payload
      end
    end
    true
  end

  # These can be comments in issues or in PRs
  def handle_issue_comment(payload)
    case payload['action']
    when 'created'
      logger.debug 'New comment to process!'

      # Is this comment in a PR?
      if pr?(payload)
        logger.debug "It's a PR"
        # If it's in a PR, does it have a command for us?
        logger.debug 'We got a +1!!!' if payload['comment']['body'] == '+1'
      else
        logger.debug "It's an issue"
      end
    else
      logger.debug payload
    end
    true
  end

  def pr?(payload)
    payload['issue'].key? 'pull_request'
  end

  # Events related to a pull request
  def handle_pull_request(payload)
    case payload['action']
    when 'reopened'
      logger.debug 'PR reopened'
    else
      logger.debug payload
    end
    true
  end

end
