"""Local Pico dashboard. Uses only Python's standard library on macOS."""
import glob
import fcntl
import json
import os
from pathlib import Path
import re
import select
import sys
import termios
import threading
import time
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import webbrowser

ROOT = Path(__file__).resolve().parent
state = {"connected": False, "waiting": False, "suspicion": 0, "event": 0, "status": "Looking for Pico…"}
lock = threading.Lock()


class Detector:
    def __init__(self):
        self.armed = True

    def update(self, value):
        if value <= 30:
            self.armed = True
        if value > 70 and self.armed:
            self.armed = False
            return True
        return False


def listen():
    detector = Detector()
    while True:
        ports = glob.glob('/dev/cu.usbmodem*')
        for port in ports:
            fd = None
            try:
                fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
                settings = termios.tcgetattr(fd)
                settings[0] = settings[1] = settings[3] = 0
                settings[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
                settings[4] = settings[5] = termios.B115200
                settings[6][termios.VMIN] = 1
                settings[6][termios.VTIME] = 0
                termios.tcsetattr(fd, termios.TCSANOW, settings)
                pending = b''
                last_reading = time.monotonic()
                while True:
                    if time.monotonic() - last_reading > 10:
                        with lock:
                            state.update(waiting=True, status='USB open, but readings paused. Check that main.py is running.')
                    if not select.select([fd], [], [], 1)[0]:
                        continue
                    try:
                        chunk = os.read(fd, 4096)
                    except BlockingIOError:
                        continue
                    if not chunk:
                        raise OSError('Pico disconnected')
                    pending += chunk
                    while b'\n' in pending:
                        line, pending = pending.split(b'\n', 1)
                        match = re.search(rb'Suspicion:\s*(\d+)%', line)
                        if match:
                            value = min(100, int(match[1]))
                            last_reading = time.monotonic()
                            with lock:
                                state.update(connected=True, waiting=False, suspicion=value, status='Pico connected')
                                if detector.update(value):
                                    state['event'] += 1
                    pending = pending[-4096:]
            except (OSError, termios.error) as error:
                print(f'USB connection error on {port}: {error}', file=sys.stderr, flush=True)
                with lock:
                    state.update(connected=False, waiting=False, suspicion=0, status=f'USB disconnected or unavailable: {error}')
            finally:
                if fd is not None:
                    os.close(fd)
        time.sleep(1)


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(ROOT), **kwargs)

    def do_GET(self):
        if self.path == '/state':
            with lock:
                body = json.dumps(state).encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Cache-Control', 'no-store')
            self.send_header('Content-Length', str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            super().do_GET()

    def log_message(self, *args):
        pass


if __name__ == '__main__':
    reader_lock = (ROOT / '.reader.lock').open('a')
    try:
        fcntl.flock(reader_lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print('Another detector is already reading the Pico. Quit it first.', file=sys.stderr)
        sys.exit(1)
    if '--native' in sys.argv:
        threading.Thread(target=listen, daemon=True).start()
        previous = None
        try:
            while True:
                with lock:
                    snapshot = json.dumps(state)
                if snapshot != previous:
                    print(snapshot, flush=True)
                    previous = snapshot
                time.sleep(0.1)
        except (KeyboardInterrupt, BrokenPipeError):
            pass
        sys.exit(0)
    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    threading.Thread(target=listen, daemon=True).start()
    url = f'http://127.0.0.1:{server.server_port}/'
    print(f'Open {url}\nKeep this window open. Press Control+C to stop.', flush=True)
    webbrowser.open(url)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.server_close()
