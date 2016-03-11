module OffsitePayments #:nodoc:
  module Integrations #:nodoc:
    module Yandexkassa
      #
      mattr_accessor :test_url
      self.test_url = 'https://demomoney.yandex.ru/eshop.xml'

      #
      mattr_accessor :production_url
      self.production_url = 'https://money.yandex.ru/eshop.xml'

      def self.service_url
        mode = OffsitePayments.mode
        case mode
          when :production
            self.production_url
          when :test
            self.test_url
          else
            raise StandardError, "Integration mode set to an invalid value: #{mode}"
        end
      end

      def self.notification(post)
        Notification.new(post)
      end

      class Helper < OffsitePayments::Helper
        mapping :account, 'customerNumber'
        mapping :amount, 'sum'
        mapping :order, 'orderNumber'
        mapping :notify_url, 'shopNotifyURL'
        mapping :shopSuccessURL, 'shopSuccessURL'
        mapping :shopFailURL, 'shopFailURL'
        # mapping :cancel_return_url, ''
        mapping :description, 'orderDetails'

        mapping :customer, :email => 'cps_email',
                :phone => 'cps_phone'

        # additional yandex.money parameters
        mapping :scid, 'scid'
        mapping :shopId, 'shopId'
        mapping :shopArticleId, 'shopArticleId'
        mapping :paymentType, 'paymentType'
        mapping :seller_id, 'seller_id'
      end

      class Notification < OffsitePayments::Notification
        attr_accessor :message

        def initialize(post, options = {})
          super
          @response_code = '200'
        end

        def complete?
          params['action'] == 'paymentAviso'
        end

        def item_id
          params['orderNumber']
        end

        def transaction_id
          params['invoiceId']
        end

        # When was this payment received by the client.
        def received_at
          params['orderCreatedDatetime']
        end

        def currency
          params['orderSumCurrencyPaycash']
        end

        def payer_email
          params['cps_email']
        end

        # the money amount we received in X.2 decimal.
        def gross
          params['orderSumAmount'].to_f
        end

        def customer_id
          params['customerNumber']
        end

        def set_response(code)
          @response_code = code
        end

        def get_response()
          @response_code
        end

        # Was this a test transaction?
        def test?
          false
        end

        def status
          case params['action']
            when 'checkOrder'
              'pending'
            when 'paymentAviso'
              'completed'
            else
              'unknown'
          end
        end

        def response
          shop_id = params['shopId']
          method = params['action']
          dt = Time.now.iso8601
          "<?xml version=\"1.0\" encoding=\"UTF-8\"?>" +
              "<#{method}Response performedDatetime=\"#{dt}\" code=\"#{@response_code}\"" +
              " invoiceId=\"#{transaction_id}\" shopId=\"#{shop_id}\" orderSumAmount=\"#{gross}\""+
              "#{" message=\"#{message}\"" if message}" +
              "/>"
        end

        # Acknowledge the transaction to YandexMoney. This method has to be called after a new
        # apc arrives. YandexMoney will verify that all the information we received are correct and will return a
        # ok or a fail.
        #
        # Example:
        #
        #   def ipn
        #     notify = YandexMoneyNotification.new(request.raw_post)
        #
        #     if notify.acknowledge(authcode)
        #       if notify.complete?
        #         ... process order ...
        #       end
        #     else
        #       ... log possible hacking attempt ...
        #     end
        #     render text: notify.response
        #

        def acknowledge(authcode = nil)
          string = [params['action'],
                    params['orderSumAmount'],
                    params['orderSumCurrencyPaycash'],
                    params['orderSumBankPaycash'],
                    params['shopId'],
                    params['invoiceId'],
                    params['customerNumber'],
                    authcode
          ].join(';')

          digest = Digest::MD5.hexdigest(string)
          res = params['md5'] == digest.upcase
          if res
            @response_code = '0'
          else
            @response_code = '1'
          end
        end

        # private
        #
        # # Take the posted data and move the relevant data into a hash
        # def parse(post)
        #   # TODO for PKCS#7 encryption
        #   hash = Hash.from_xml(post)
        #   self.params = hash.first[1].deep_dup
        #   self.params['action'] = hash.first[0][/(.*)Request/,1]
        #
        #   # @raw = post.to_s
        #   # for line in @raw.split('&')
        #   #   key, value = *line.scan(%r{^([A-Za-z0-9_.-]+)\=(.*)$}).flatten
        #   #   # to divide raw values from other
        #   #   params['' + key] = CGI.unescape(value.to_s) if key.present?
        #   # end
        # end
      end
    end
  end
end