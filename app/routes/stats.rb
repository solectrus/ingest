class StatsRoute < BaseRoute
  helpers StatsHelpers, ActiveSupport::NumberHelper

  get '/' do
    protected!

    # The header renders before the page, so the badge cannot pick up the
    # status while the fields render. The route reads it first, and the
    # helper memoizes, so the page costs no extra query.
    @page_status = page_status

    erb :stats
  end
end
