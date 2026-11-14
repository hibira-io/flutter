// The backend for the example app's Chat tab, and a web page for the same
// room, with no dependencies: node server.mjs (Node 18+).
//
// It signs presence-chat subscriptions with your app secret. Who the user is
// comes from ?user= here to keep the example short; in your app, take it
// from your own sign-in instead.
import { createHmac } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { createServer } from 'node:http';

const { HIBIRA_APP_KEY: key, HIBIRA_APP_SECRET: secret } = process.env;
const port = Number(process.env.PORT ?? 8000);
if (!key || !secret) throw new Error('set HIBIRA_APP_KEY and HIBIRA_APP_SECRET');

const page = readFileSync(new URL('index.html', import.meta.url), 'utf8')
  .replace('YOUR_APP_KEY', key);

createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  res.setHeader('Access-Control-Allow-Origin', '*');
  if (req.method === 'POST' && url.pathname === '/hibira/auth') {
    let body = '';
    for await (const chunk of req) body += chunk;
    const form = new URLSearchParams(body);
    const socketId = form.get('socket_id');
    const channel = form.get('channel_name');
    const name = (url.searchParams.get('user') ?? 'Guest').slice(0, 20);
    if (channel !== 'presence-chat' || !/^\d+\.\d+$/.test(socketId ?? '')) {
      res.writeHead(403).end();
      return;
    }
    const channelData = JSON.stringify({ user_id: name.toLowerCase(), user_info: { name } });
    const signature = createHmac('sha256', secret)
      .update(`${socketId}:${channel}:${channelData}`)
      .digest('hex');
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ auth: `${key}:${signature}`, channel_data: channelData }));
    return;
  }
  if (req.method === 'OPTIONS') {
    res.writeHead(204, { 'Access-Control-Allow-Headers': 'content-type' }).end();
    return;
  }
  res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' }).end(page);
}).listen(port, () => console.log(`http://localhost:${port}/?user=Leo`));
