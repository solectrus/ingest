describe SessionHelper do
  # Minimal stand-in for the Sinatra context the helper runs in
  subject(:helper) do
    helper_class.new.tap do |instance|
      instance.request = request_double
      instance.response = response_double
    end
  end

  let(:helper_class) do
    Class.new do
      include SessionHelper

      attr_accessor :request, :response, :redirected_to

      def redirect(target)
        self.redirected_to = target
      end

      def to(target)
        target
      end
    end
  end

  let(:request_double) do
    Struct
      .new(:path, :cookies) do
        def secure? = false
      end
      .new(path, {})
  end

  let(:response_double) do
    Struct
      .new(:cookies) do
        def set_cookie(name, options)
          cookies[name] = options
        end
      end
      .new({})
  end

  let(:path) { '/' }
  let(:password) { 'secret' }

  # `password` reads STATS_PASSWORD, so the environment sets it
  before { stub_const('ENV', ENV.to_hash.merge('STATS_PASSWORD' => password)) }

  describe '#protected!' do
    context 'without a password' do
      let(:password) { '' }

      before { helper.protected! }

      it 'does not redirect' do
        expect(helper.redirected_to).to be_nil
      end
    end

    context 'with a wrong password' do
      before { helper.protected! }

      it 'redirects to the login form' do
        expect(helper.redirected_to).to eq('/login')
      end

      it 'remembers the requested page' do
        expect(helper.response.cookies['return_to']).to include(value: '/')
      end
    end

    context 'when the login form itself is protected' do
      let(:path) { '/login' }

      before { helper.protected! }

      it 'remembers the root page instead of the login form' do
        expect(helper.response.cookies['return_to']).to include(value: '/')
      end
    end
  end

  describe '#correct_password?' do
    context 'without a password' do
      let(:password) { '' }

      it 'accepts nothing, so the login form stays closed' do
        expect(helper).not_to be_correct_password('')
      end
    end
  end

  describe '#authorized?' do
    it 'accepts a matching cookie' do
      helper.request.cookies['password'] = 'secret'

      expect(helper).to be_authorized
    end

    it 'rejects a wrong cookie' do
      helper.request.cookies['password'] = 'wrong'

      expect(helper).not_to be_authorized
    end
  end
end
