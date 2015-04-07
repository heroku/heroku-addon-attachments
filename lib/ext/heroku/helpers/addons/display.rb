module Heroku::Helpers
  module Addons
    module Display
      def format_price(price)
        if price['cents'] == 0
          'free'
        else
          '$%.2f/%s' % [(price['cents'] / 100.0), price['unit']]
        end
      end
    end
  end
end
