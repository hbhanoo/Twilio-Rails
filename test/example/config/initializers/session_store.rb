# Be sure to restart your server when you modify this file.

# Your secret key for verifying cookie session data integrity.
# If you change this key, all old sessions will become invalid!
# Make sure the secret is at least 30 characters and all random, 
# no regular words or you'll be exposed to dictionary attacks.
ActionController::Base.session = {
  :key         => '_example_session',
  :secret      => '2c1d7e3c41ff13300dd5f19519ceef19ad10787ce1bcf38f9ef5a430bf2bd7a239547301aa433cfd47db542d32a251d9245f4dcb8d38cb3b6802013fe955a278'
}

# Use the database for sessions instead of the cookie-based default,
# which shouldn't be used to store highly confidential information
# (create the session table with "rake db:sessions:create")
# ActionController::Base.session_store = :active_record_store
