"""Local-only fixture for device tests. Reach through adb reverse tcp:18679 tcp:18679."""
import argparse
import json
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--env-file', type=Path, required=True)
    parser.add_argument('--endpoint', required=True)
    parser.add_argument('--device', required=True)
    parser.add_argument('--output', type=Path, required=True)
    options = parser.parse_args()
    credentials = dict(line.split('=', 1) for line in options.env_file.read_text().splitlines() if '=' in line)
    options.output.mkdir(parents=True, exist_ok=True)
    project = Path(__file__).resolve().parents[2]

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            if self.path == '/config':
                subprocess.run([
                    'adb', '-s', options.device, 'shell', 'pm', 'grant',
                    'app.dingdong.dingdong', 'android.permission.POST_NOTIFICATIONS',
                ], check=True, stdout=subprocess.DEVNULL)
                result = {'endpoint': options.endpoint,
                          'sendToken': credentials['DINGDONG_SEND_TOKEN'],
                          'readToken': credentials['DINGDONG_READ_TOKEN'],
                          'html': (project / 'examples/report.html').read_text(encoding='utf-8')}
            elif self.path in ('/background', '/foreground'):
                action = ['input', 'keyevent', 'KEYCODE_HOME']
                if self.path == '/foreground':
                    action = ['am', 'start', '-n', 'app.dingdong.dingdong/.MainActivity']
                subprocess.run(['adb', '-s', options.device, 'shell', *action],
                               check=True, stdout=subprocess.DEVNULL)
                result = {'completed': True}
            elif self.path.startswith('/capture/'):
                name = self.path.rsplit('/', 1)[1]
                if not name.replace('-', '').isalnum():
                    self.send_error(400)
                    return
                screenshot = subprocess.check_output(['adb', '-s', options.device, 'exec-out', 'screencap', '-p'])
                offset = screenshot.find(b'\x89PNG\r\n\x1a\n')
                if offset < 0:
                    self.send_error(500)
                    return
                (options.output / (name + '.png')).write_bytes(screenshot[offset:])
                result = {'saved': True}
            else:
                self.send_error(404)
                return
            encoded = json.dumps(result).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)

    print('Device fixture listening on 127.0.0.1:18679', flush=True)
    ThreadingHTTPServer(('127.0.0.1', 18679), Handler).serve_forever()


if __name__ == '__main__':
    main()
