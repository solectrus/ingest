class StatsRoute < BaseRoute
  helpers StatsHelpers, ActiveSupport::NumberHelper

  # Every tab has a path of its own, and the routes come from the same list
  # that renders the tab bar. A path keeps the URL readable, a bookmark names
  # the tab, and an unknown name gives a 404 instead of a silent fallback.
  StatsHelpers::TABS.each do |tab|
    get tab[:path] do
      protected!

      @current_tab = tab[:id]

      # The header renders before the page, so the badge cannot pick up the
      # status while the fields render. The route reads it first, and the
      # helper memoizes, so the page costs no extra query.
      @page_status = page_status

      erb :stats
    end
  end
end
