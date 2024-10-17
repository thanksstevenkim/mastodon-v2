# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FetchLinkCardService do
  subject { described_class.new }

  let(:html) { '<!doctype html><title>Hello world</title>' }
  let(:oembed_cache) { nil }

  before do
    stub_request(:get, 'http://example.com/html').to_return(headers: { 'Content-Type' => 'text/html' }, body: html)
    stub_request(:get, 'http://example.com/not-found').to_return(status: 404, headers: { 'Content-Type' => 'text/html' }, body: html)
    stub_request(:get, 'http://example.com/text').to_return(status: 404, headers: { 'Content-Type' => 'text/plain' }, body: 'Hello')
    stub_request(:get, 'http://example.com/redirect').to_return(status: 302, headers: { 'Location' => 'http://example.com/html' })
    stub_request(:get, 'http://example.com/redirect-to-404').to_return(status: 302, headers: { 'Location' => 'http://example.com/not-found' })
    stub_request(:get, 'http://example.com/oembed?url=http://example.com/html').to_return(headers: { 'Content-Type' => 'application/json' }, body: '{ "version": "1.0", "type": "link", "title": "oEmbed title" }')
    stub_request(:get, 'http://example.com/oembed?format=json&url=http://example.com/html').to_return(headers: { 'Content-Type' => 'application/json' }, body: '{ "version": "1.0", "type": "link", "title": "oEmbed title" }')

    stub_request(:get, 'http://example.xn--fiqs8s')
    stub_request(:get, 'http://example.com/日本語')
    stub_request(:get, 'http://example.com/test?data=file.gpx%5E1')
    stub_request(:get, 'http://example.com/test-')

    stub_request(:get, 'http://example.com/sjis').to_return(request_fixture('sjis.txt'))
    stub_request(:get, 'http://example.com/sjis_with_wrong_charset').to_return(request_fixture('sjis_with_wrong_charset.txt'))
    stub_request(:get, 'http://example.com/koi8-r').to_return(request_fixture('koi8-r.txt'))
    stub_request(:get, 'http://example.com/windows-1251').to_return(request_fixture('windows-1251.txt'))
    stub_request(:get, 'http://example.com/low_confidence_latin1').to_return(request_fixture('low_confidence_latin1.txt'))
    stub_request(:get, 'http://example.com/latin1_posing_as_utf8_broken').to_return(request_fixture('latin1_posing_as_utf8_broken.txt'))
    stub_request(:get, 'http://example.com/latin1_posing_as_utf8_recoverable').to_return(request_fixture('latin1_posing_as_utf8_recoverable.txt'))
    stub_request(:get, 'http://example.com/aergerliche-umlaute').to_return(request_fixture('redirect_with_utf8_url.txt'))
    stub_request(:get, 'http://example.com/page_without_title').to_return(request_fixture('page_without_title.txt'))
    stub_request(:get, 'http://example.com/long_canonical_url').to_return(request_fixture('long_canonical_url.txt'))
    stub_request(:get, 'http://example.com/alternative_utf8_spelling_in_header').to_return(request_fixture('alternative_utf8_spelling_in_header.txt'))

    # YouTube 관련 스터브 추가
    stub_request(:get, %r{https://www\.youtube\.com/oembed\?.*})
      .to_return(status: 200, body: '{"version":"1.0","type":"video","title":"YouTube Video","author_name":"YouTube User"}', headers: { 'Content-Type' => 'application/json' })

    stub_request(:get, %r{https://music\.youtube\.com/oembed\?.*})
      .to_return(status: 200, body: '{"version":"1.0","type":"video","title":"YouTube Music Track","author_name":"Artist"}', headers: { 'Content-Type' => 'application/json' })

    # 이미 존재하는 YouTube 스터브 수정
    stub_request(:get, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ').to_return(
      status: 200,
      body: '<html><head><meta property="og:title" content="Rick Astley - Never Gonna Give You Up (Official Music Video)"><meta property="og:description" content="The official video for "Never Gonna Give You Up" by Rick Astley"><meta property="og:image" content="https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg"></head></html>',
      headers: { 'Content-Type' => 'text/html' }
    )

    # YouTube Music 스터브 추가
    stub_request(:get, 'https://music.youtube.com/watch?v=dQw4w9WgXcQ').to_return(
      status: 200,
      body: '<html><head><meta property="og:title" content="Never Gonna Give You Up"><meta property="og:description" content="Provided to YouTube by Sony Music Entertainment"><meta property="og:image" content="https://lh3.googleusercontent.com/TY8x12EzPTvM8gA9OOIVFguHv4Di5BuZe6plYGVz2Q-OghEgEYEIYsz7pEcD_o1bFBMDQPmEpA=w544-h544-p-l90-rj"></head></html>',
      headers: { 'Content-Type' => 'text/html' }
    )

    # 잘못된 YouTube URL에 대한 스터브
    stub_request(:get, 'https://www.youtube.com/watch?v=invalid').to_return(status: 404)

    Rails.cache.write('oembed_endpoint:example.com', oembed_cache) if oembed_cache

    subject.call(status)
  end

  context 'with a local status' do
    context 'with URL of a regular HTML page' do
      let(:status) { Fabricate(:status, text: 'http://example.com/html') }

      it 'creates preview card' do
        expect(status.preview_card).to_not be_nil
        expect(status.preview_card.url).to eq 'http://example.com/html'
        expect(status.preview_card.title).to eq 'Hello world'
      end
    end

    context 'with URL of a page with no title' do
      let(:status) { Fabricate(:status, text: 'http://example.com/html') }
      let(:html) { '<!doctype html><title></title>' }

      it 'does not create a preview card' do
        expect(status.preview_card).to be_nil
      end
    end

    context 'with a URL of a plain-text page' do
      let(:status) { Fabricate(:status, text: 'http://example.com/text') }

      it 'does not create a preview card' do
        expect(status.preview_card).to be_nil
      end
    end

    context 'with multiple URLs' do
      let(:status) { Fabricate(:status, text: 'ftp://example.com http://example.com/html http://example.com/text') }

      it 'fetches the first valid URL' do
        expect(a_request(:get, 'http://example.com/html')).to have_been_made
      end

      it 'does not fetch the second valid URL' do
        expect(a_request(:get, 'http://example.com/text/')).to_not have_been_made
      end
    end

    context 'with a redirect URL' do
      let(:status) { Fabricate(:status, text: 'http://example.com/redirect') }

      it 'follows redirect' do
        expect(a_request(:get, 'http://example.com/redirect')).to have_been_made.once
        expect(a_request(:get, 'http://example.com/html')).to have_been_made.once
      end

      it 'creates preview card' do
        expect(status.preview_card).to_not be_nil
        expect(status.preview_card.url).to eq 'http://example.com/html'
        expect(status.preview_card.title).to eq 'Hello world'
      end
    end

    context 'with a broken redirect URL' do
      let(:status) { Fabricate(:status, text: 'http://example.com/redirect-to-404') }

      it 'follows redirect' do
        expect(a_request(:get, 'http://example.com/redirect-to-404')).to have_been_made.once
        expect(a_request(:get, 'http://example.com/not-found')).to have_been_made.once
      end

      it 'does not create a preview card' do
        expect(status.preview_card).to be_nil
      end
    end

    context 'with a redirect URL with faulty encoding' do
      let(:status) { Fabricate(:status, text: 'http://example.com/aergerliche-umlaute') }

      it 'does not create a preview card' do
        expect(status.preview_card).to be_nil
      end
    end

    context 'with a page that has no title' do
      let(:status) { Fabricate(:status, text: 'http://example.com/page_without_title') }

      it 'does not create a preview card' do
        expect(status.preview_card).to be_nil
      end
    end

    context 'with a 404 URL' do
      let(:status) { Fabricate(:status, text: 'http://example.com/not-found') }

      it 'does not create a preview card' do
        expect(status.preview_card).to be_nil
      end
    end

    context 'with an IDN URL' do
      let(:status) { Fabricate(:status, text: 'Check out http://example.中国') }

      it 'fetches the URL' do
        expect(a_request(:get, 'http://example.xn--fiqs8s/')).to have_been_made.once
      end
    end

    context 'with a URL of a page in Shift JIS encoding' do
      let(:status) { Fabricate(:status, text: 'Check out http://example.com/sjis') }

      it 'decodes the HTML' do
        expect(status.preview_card.title).to eq('SJISのページ')
      end
    end

    context 'with a URL of a page in Shift JIS encoding labeled as UTF-8' do
      let(:status) { Fabricate(:status, text: 'Check out http://example.com/sjis_with_wrong_charset') }

      it 'decodes the HTML despite the wrong charset header' do
        expect(status.preview_card.title).to eq('SJISのページ')
      end
    end

    context 'with a URL of a page in KOI8-R encoding' do
      let(:status) { Fabricate(:status, text: 'Check out http://example.com/koi8-r') }

      it 'decodes the HTML' do
        expect(status.preview_card.title).to eq('Московя начинаетъ только въ XVI ст. привлекать внимане иностранцевъ.')
      end
    end

    context 'with a URL of a page in Windows-1251 encoding' do
      let(:status) { Fabricate(:status, text: 'Check out http://example.com/windows-1251') }

      it 'decodes the HTML' do
        expect(status.preview_card.title).to eq('сэмпл текст')
      end
    end

    context 'with a URL of a page in ISO-8859-1 encoding, that charlock_holmes cannot detect' do
      context 'when encoding in http header is correct' do
        let(:status) { Fabricate(:status, text: 'Check out http://example.com/low_confidence_latin1') }

        it 'decodes the HTML' do
          expect(status.preview_card.title).to eq("Tofu á l'orange")
        end
      end

      context 'when encoding in http header is incorrect' do
        context 'when encoding problems appear in unrelated tags' do
          let(:status) { Fabricate(:status, text: 'Check out http://example.com/latin1_posing_as_utf8_recoverable') }

          it 'decodes the HTML' do
            expect(status.preview_card.title).to eq('Tofu with orange sauce')
          end
        end

        context 'when encoding problems appear in title tag' do
          let(:status) { Fabricate(:status, text: 'Check out http://example.com/latin1_posing_as_utf8_broken') }

          it 'creates a preview card anyway that replaces invalid bytes with U+FFFD (replacement char)' do
            expect(status.preview_card.title).to eq("Tofu � l'orange")
          end
        end
      end
    end

    context 'with a Japanese path URL' do
      let(:status) { Fabricate(:status, text: 'テストhttp://example.com/日本語') }

      it 'fetches the URL' do
        expect(a_request(:get, 'http://example.com/日本語')).to have_been_made.once
      end
    end

    context 'with a hyphen-suffixed URL' do
      let(:status) { Fabricate(:status, text: 'test http://example.com/test-') }

      it 'fetches the URL' do
        expect(a_request(:get, 'http://example.com/test-')).to have_been_made.once
      end
    end

    context 'with a caret-suffixed URL' do
      let(:status) { Fabricate(:status, text: 'test http://example.com/test?data=file.gpx^1') }

      it 'fetches the URL' do
        expect(a_request(:get, 'http://example.com/test?data=file.gpx%5E1')).to have_been_made.once
      end

      it 'does not strip the caret before fetching' do
        expect(a_request(:get, 'http://example.com/test?data=file.gpx')).to_not have_been_made
      end
    end

    context 'with a non-isolated URL' do
      let(:status) { Fabricate(:status, text: 'testhttp://example.com/sjis') }

      it 'does not fetch URLs not isolated from their surroundings' do
        expect(a_request(:get, 'http://example.com/sjis')).to_not have_been_made
      end
    end

    context 'with a URL of a page with oEmbed support' do
      let(:html) { '<!doctype html><title>Hello world</title><link rel="alternate" type="application/json+oembed" href="http://example.com/oembed?url=http://example.com/html">' }
      let(:status) { Fabricate(:status, text: 'http://example.com/html') }

      it 'fetches the oEmbed URL' do
        expect(a_request(:get, 'http://example.com/oembed?url=http://example.com/html')).to have_been_made.once
      end

      it 'creates preview card' do
        expect(status.preview_card).to_not be_nil
        expect(status.preview_card.url).to eq 'http://example.com/html'
        expect(status.preview_card.title).to eq 'oEmbed title'
      end

      context 'when oEmbed endpoint cache populated' do
        let(:oembed_cache) { { endpoint: 'http://example.com/oembed?format=json&url={url}', format: :json } }

        it 'uses the cached oEmbed response' do
          expect(a_request(:get, 'http://example.com/oembed?url=http://example.com/html')).to_not have_been_made
          expect(a_request(:get, 'http://example.com/oembed?format=json&url=http://example.com/html')).to have_been_made
        end

        it 'creates preview card' do
          expect(status.preview_card).to_not be_nil
          expect(status.preview_card.url).to eq 'http://example.com/html'
          expect(status.preview_card.title).to eq 'oEmbed title'
        end
      end

      # If the original HTML URL for whatever reason (e.g. DOS protection) redirects to
      # an error page, we can still use the cached oEmbed but should not use the
      # redirect URL on the card.
      context 'when oEmbed endpoint cache populated but page returns 404' do
        let(:status) { Fabricate(:status, text: 'http://example.com/redirect-to-404') }
        let(:oembed_cache) { { endpoint: 'http://example.com/oembed?url=http://example.com/html', format: :json } }

        it 'uses the cached oEmbed response' do
          expect(a_request(:get, 'http://example.com/oembed?url=http://example.com/html')).to have_been_made
        end

        it 'creates preview card' do
          expect(status.preview_card).to_not be_nil
          expect(status.preview_card.title).to eq 'oEmbed title'
        end

        it 'uses the original URL' do
          expect(status.preview_card&.url).to eq 'http://example.com/redirect-to-404'
        end
      end
    end

    context 'with a URL of a page that includes a canonical URL too long for PostgreSQL unique indexes' do
      let(:status) { Fabricate(:status, text: 'test http://example.com/long_canonical_url') }

      it 'does not create a preview card' do
        expect(status.preview_card).to be_nil
      end
    end

    context 'with a URL where the `Content-Type` header uses `utf8` instead of `utf-8`' do
      let(:status) { Fabricate(:status, text: 'test http://example.com/alternative_utf8_spelling_in_header') }

      it 'does not create a preview card' do
        expect(status.preview_card.title).to eq 'Webserver Configs R Us'
      end
    end

    context 'with a YouTube URL' do
      let(:youtube_url) { 'https://www.youtube.com/watch?v=dQw4w9WgXcQ' }
      let(:status) { Fabricate(:status, text: youtube_url) }

      before do
        stub_request(:get, youtube_url).to_return(
          status: 200,
          body: '<html><head><meta property="og:title" content="Rick Astley - Never Gonna Give You Up (Official Music Video)"><meta property="og:description" content="The official video for "Never Gonna Give You Up" by Rick Astley"><meta property="og:image" content="https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg"></head></html>',
          headers: { 'Content-Type' => 'text/html' }
        )
      end

      it 'creates a preview card with YouTube metadata' do
        subject.call(status)
        expect(status.preview_card).to_not be_nil
        expect(status.preview_card.provider_name).to eq('YouTube')
        expect(status.preview_card.title).to eq('Rick Astley - Never Gonna Give You Up (Official Music Video)')
        expect(status.preview_card.image_remote_url).to eq('https://i.ytimg.com/vi/dQw4w9WgXcQ/maxresdefault.jpg')
      end
    end

    context 'with a YouTube Music URL' do
      let(:youtube_music_url) { 'https://music.youtube.com/watch?v=dQw4w9WgXcQ' }
      let(:status) { Fabricate(:status, text: youtube_music_url) }

      before do
        stub_request(:get, youtube_music_url).to_return(
          status: 200,
          body: '<html><head><meta property="og:title" content="Never Gonna Give You Up"><meta property="og:description" content="Provided to YouTube by Sony Music Entertainment"><meta property="og:image" content="https://lh3.googleusercontent.com/TY8x12EzPTvM8gA9OOIVFguHv4Di5BuZe6plYGVz2Q-OghEgEYEIYsz7pEcD_o1bFBMDQPmEpA=w544-h544-p-l90-rj"></head></html>',
          headers: { 'Content-Type' => 'text/html' }
        )
      end

      it 'creates a preview card with YouTube Music metadata' do
        subject.call(status)
        expect(status.preview_card).to_not be_nil
        expect(status.preview_card.provider_name).to eq('YouTube Music')
        expect(status.preview_card.title).to eq('Never Gonna Give You Up')
        expect(status.preview_card.image_remote_url).to include('lh3.googleusercontent.com')
      end
    end

    context 'with an invalid YouTube URL' do
      let(:invalid_youtube_url) { 'https://www.youtube.com/watch?v=invalid' }
      let(:status) { Fabricate(:status, text: invalid_youtube_url) }

      before do
        stub_request(:get, invalid_youtube_url).to_return(status: 404)
        allow(Rails.logger).to receive(:error)
        allow(Rails.logger).to receive(:error)
      end

      it 'does not create a preview card' do
        subject.call(status)
        expect(status.preview_card).to be_nil
      end

      it 'logs an error' do
        subject.call(status)
        expect(Rails.logger).to have_received(:error).with(/Error fetching YouTube metadata:/)
      end
    end
  end

  context 'with a remote status' do
    let(:status) do
      Fabricate(:status, account: Fabricate(:account, domain: 'example.com'), text: <<-TEXT)
      Habt ihr ein paar gute Links zu <a>foo</a>
      #<span class="tag"><a href="https://quitter.se/tag/wannacry" target="_blank" rel="tag noopener noreferrer" title="https://quitter.se/tag/wannacry">Wannacry</a></span> herumfliegen?
      Ich will mal unter <br> <a href="http://example.com/not-found" target="_blank" rel="noopener noreferrer" title="http://example.com/not-found">http://example.com/not-found</a> was sammeln. !
      <a href="http://sn.jonkman.ca/group/416/id" target="_blank" rel="noopener noreferrer" title="http://sn.jonkman.ca/group/416/id">security</a>&nbsp;
      TEXT
    end

    it 'parses out URLs' do
      expect(a_request(:get, 'http://example.com/not-found')).to have_been_made.once
    end

    it 'ignores URLs to hashtags' do
      expect(a_request(:get, 'https://quitter.se/tag/wannacry')).to_not have_been_made
    end
  end
end
