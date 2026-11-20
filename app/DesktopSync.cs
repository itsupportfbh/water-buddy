using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

// Read-only, token-authenticated bridge; never binds a LAN interface.
public sealed class WaterBuddySync : IDisposable {
    const string Origin = "https://water-buddy-reminder.vercel.app";
    readonly TcpListener listener;
    readonly string token;
    string snapshot = "{}";
    volatile bool running = true;
    public WaterBuddySync(string secret, int port) {
        token = secret;
        listener = new TcpListener(IPAddress.Loopback, port);
        listener.Start();
        var thread = new Thread(Serve); thread.IsBackground = true; thread.Start();
    }
    public void Publish(string json) { Interlocked.Exchange(ref snapshot, json); }
    void Serve() {
        while (running) {
            try { using (var client = listener.AcceptTcpClient()) Handle(client); }
            catch { if (!running) return; }
        }
    }
    void Handle(TcpClient client) {
        client.ReceiveTimeout = 2000; client.SendTimeout = 2000;
        using (var stream = client.GetStream()) {
            // Bound header size and total read time (including slow clients).
            var bytes = new MemoryStream(); var deadline = DateTime.UtcNow.AddSeconds(2);
            int value; string headers = "";
            while (bytes.Length < 8192 && DateTime.UtcNow < deadline && (value = stream.ReadByte()) >= 0) {
                bytes.WriteByte((byte)value);
                if (value == 10) { headers = Encoding.ASCII.GetString(bytes.ToArray()); if (headers.EndsWith("\r\n\r\n")) break; }
            }
            if (!headers.EndsWith("\r\n\r\n")) return;
            var lines = headers.Split(new[] { "\r\n" }, StringSplitOptions.None);
            string origin = "", auth = "", host = "";
            foreach (var line in lines) {
                int split = line.IndexOf(':'); if (split < 0) continue;
                var name = line.Substring(0, split).ToLowerInvariant(); var val = line.Substring(split+1).Trim();
                if (name == "origin") origin = val;
                if (name == "authorization") auth = val;
                if (name == "host") host = val;
            }
            bool allowed = origin == Origin && host == "127.0.0.1:" + ((IPEndPoint)listener.LocalEndpoint).Port;
            bool preflight = lines[0] == "OPTIONS /v1/drinks HTTP/1.1";
            bool get = lines[0] == "GET /v1/drinks HTTP/1.1";
            int status = !allowed ? 403 : preflight ? 204 : !get ? 404 : auth != "Bearer " + token ? 401 : 200;
            var body = Encoding.UTF8.GetBytes(status == 200 ? snapshot : "");
            var cors = allowed ? "Access-Control-Allow-Origin: " + Origin + "\r\nAccess-Control-Allow-Methods: GET, OPTIONS\r\nAccess-Control-Allow-Headers: Authorization\r\nAccess-Control-Allow-Private-Network: true\r\nVary: Origin\r\n" : "";
            var response = Encoding.ASCII.GetBytes("HTTP/1.1 " + status + " " + (status==200?"OK":status==204?"No Content":"Rejected") + "\r\n" + cors + "Cache-Control: no-store\r\nContent-Type: application/json\r\nConnection: close\r\nContent-Length: " + body.Length + "\r\n\r\n");
            stream.Write(response,0,response.Length); stream.Write(body,0,body.Length);
        }
    }
    public void Dispose() { running = false; listener.Stop(); }
}
