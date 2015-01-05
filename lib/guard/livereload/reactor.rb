require 'multi_json'

module Guard
  class LiveReload < Plugin
    class Reactor
      attr_reader :web_sockets, :thread, :options, :connections_count

      def initialize(options)
        @web_sockets       = []
        @options           = options
        @thread            = Thread.new { _start_reactor }
        @connections_count = 0
      end

      def stop
        thread.kill
      end

      def reload_browser(paths = [])
        msg = "Reloading browser: #{paths.join(' ')}"
        Compat::UI.info msg
        if options[:notify]
          Compat::UI.notify(msg, title: 'Reloading browser', image: :success)
        end

        paths.each do |path|
          data = _data(path)
          Compat::UI.debug(data)
          web_sockets.each { |ws| ws.send(MultiJson.encode(_alter_live_css_path(data))) }
        end
      end

      private

      def _alter_live_css_path(data)
        unless options[:apply_sass_live] && /\.s[ac]ss$/ =~ data[:path]
          return data
        end

        path = data[:path]
        new_filename = case path
                       when /\.css\.(s[ac]ss)$/ then File.basename(path, ".css.#{$1}")
                       when /\.(s[ac]ss)$/ then File.basename(path, ".#{$1}")
                       else File.basename(path)
                       end

        data[:path] = "#{File.dirname(path)}/#{new_filename}.css"
        data
      end

      def _data(path)
        data = {
          command: 'reload',
          path:    "#{Dir.pwd}/#{path}",
          liveCSS: options[:apply_css_live]
        }
        if options[:override_url] && File.exist?(path)
          data[:overrideURL] = '/' + path
        end
        data
      end

      def _start_reactor
        EventMachine.epoll
        EventMachine.run do
          EventMachine.start_server(options[:host], options[:port], WebSocket, {}) do |ws|
            ws.onopen    { _connect(ws) }
            ws.onclose   { _disconnect(ws) }
            ws.onmessage { |msg| _print_message(msg) }
          end
          Compat::UI.info 'LiveReload is waiting for a browser to connect.'
        end
      end

      def _connect(ws)
        @connections_count += 1
        Compat::UI.info 'Browser connected.' if connections_count == 1

        ws.send MultiJson.encode(
          command:    'hello',
          protocols:  ['http://livereload.com/protocols/official-7'],
          serverName: 'guard-livereload'
        )
        @web_sockets << ws
      rescue
        Compat::UI.error $!
        Compat::UI.error $!.backtrace
      end

      def _disconnect(ws)
        @web_sockets.delete(ws)
      end

      def _print_message(message)
        message = MultiJson.decode(message)
        Compat::UI.info "Browser URL: #{message['url']}" if message['command'] == 'url'
      end
    end
  end
end
