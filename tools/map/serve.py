import http.server
import socketserver
import webbrowser
import os
import json

PORT = 8080
BASE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(BASE_DIR)

class CustomHandler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(200)
        self.end_headers()

    def do_POST(self):
        if self.path == '/api/save':
            content_length = int(self.headers.get('Content-Length', 0))
            body = self.rfile.read(content_length).decode('utf-8')
            try:
                data = json.loads(body)
                if 'buildings' in data:
                    with open('tools/map/usst_516_buildings.geojson', 'w', encoding='utf-8') as f:
                        json.dump(data['buildings'], f, ensure_ascii=False, indent=2)
                if 'roads' in data:
                    with open('tools/map/usst_516_roads.geojson', 'w', encoding='utf-8') as f:
                        json.dump(data['roads'], f, ensure_ascii=False, indent=2)
                if 'pois' in data:
                    with open('tools/map/usst_516_pois.geojson', 'w', encoding='utf-8') as f:
                        json.dump(data['pois'], f, ensure_ascii=False, indent=2)

                self.send_response(200)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({'status': 'ok', 'message': 'Saved successfully'}).encode('utf-8'))
                print("Successfully saved geojson updates from browser editor!")
            except Exception as e:
                self.send_response(500)
                self.send_header('Content-Type', 'application/json')
                self.end_headers()
                self.wfile.write(json.dumps({'status': 'error', 'message': str(e)}).encode('utf-8'))
        else:
            self.send_response(404)
            self.end_headers()

print(f"Starting USST Campus Map Editor Server at http://localhost:{PORT}/tools/map/viewer.html")
webbrowser.open(f"http://localhost:{PORT}/tools/map/viewer.html")

with socketserver.TCPServer(("", PORT), CustomHandler) as httpd:
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nServer stopped.")
