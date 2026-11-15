import http.server, json, datetime, sys
# Fake Xtream provider for testing ONAIR without a real account: one connection, short
# programmes, public Apple/Mux test streams. python3 scripts/fake-provider.py (port 18765).
PORT = 18765
STREAMS = [
  ("Test One", "t1", "https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_fmp4/master.m3u8"),
  ("Test Two", "t2", "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8"),
  ("Test Three", "t3", "https://devstreaming-cdn.apple.com/videos/streaming/examples/bipbop_16x9/bipbop_16x9_variant.m3u8"),
] + [(f"Filler {i}", f"f{i}", "https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8") for i in range(4, 16)]
STREAMS = [(n, i, u + ("?n=" + i if i.startswith("f") else "")) for n, i, u in STREAMS]
START = datetime.datetime.now(datetime.timezone.utc)
def fmt(d): return d.strftime("%Y%m%d%H%M%S +0000")
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): sys.stderr.write("REQ " + self.path.split("?")[0] + "\n")
    def send(self, body, ctype):
        b = body.encode(); self.send_response(200); self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        p = self.path.split("?")[0]
        if p == "/get.php":
            out = "#EXTM3U\n" + "".join(f'#EXTINF:-1 tvg-id="{i}" tvg-name="{n}" group-title="TEST",{n}\n{u}\n' for n, i, u in STREAMS)
            self.send(out, "audio/x-mpegurl")
        elif p == "/player_api.php":
            action = dict(x.split("=", 1) for x in self.path.split("?", 1)[-1].split("&") if "=" in x).get("action")
            if action == "get_live_categories":
                self.send(json.dumps([{"category_id": "1", "category_name": "TEST"}]), "application/json")
            elif action == "get_live_streams":
                self.send(json.dumps([{"stream_id": k + 1, "name": n, "category_id": "1", "epg_channel_id": i}
                                      for k, (n, i, u) in enumerate(STREAMS)]), "application/json")
            else:
                self.send(json.dumps({"user_info": {"auth": 1, "active_cons": "0", "max_connections": "1", "status": "Active"}, "server_info": {}}), "application/json")
        elif p.startswith("/live/"):
            # Xtream stream links redirect to the real test stream, like providers' session URLs.
            try:
                k = int(p.rsplit("/", 1)[-1].split(".")[0]) - 1
                self.send_response(302); self.send_header("Location", STREAMS[k][2]); self.end_headers()
            except (ValueError, IndexError):
                self.send_response(404); self.end_headers()
        elif p == "/xmltv.php":
            now = datetime.datetime.now(datetime.timezone.utc)   # programmes always around now
            progs = ""
            for n, i, u in STREAMS:
                a = now - datetime.timedelta(minutes=30); b = now + datetime.timedelta(seconds=75); c = b + datetime.timedelta(minutes=45)
                progs += f'<programme start="{fmt(a)}" stop="{fmt(b)}" channel="{i}"><title>{n} Evening Show</title></programme>'
                progs += f'<programme start="{fmt(b)}" stop="{fmt(c)}" channel="{i}"><title>{n} Late News</title></programme>'
            self.send(f'<?xml version="1.0"?><tv>{progs}</tv>', "application/xml")
        else:
            self.send_response(404); self.end_headers()
http.server.ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
