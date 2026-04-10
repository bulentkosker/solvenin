// Vercel Serverless Function — proxies Brent crude price from Yahoo Finance.
// Called by the dashboard ticker as GET /api/oil-price
// Returns: { price: number, change: string|null } or { error: string }
//
// Why a proxy? Yahoo Finance v8 has no CORS headers, so browsers block it.
// This runs server-side on Vercel's edge, fetches the data, and returns it
// with the correct CORS headers (same-origin, no extra config needed).

export default async function handler(req, res) {
  // Only GET
  if (req.method !== 'GET') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // Cache: tell Vercel CDN + browser to cache for 10 min, stale-while-revalidate 20 min
  res.setHeader('Cache-Control', 's-maxage=600, stale-while-revalidate=1200');

  try {
    const url = 'https://query1.finance.yahoo.com/v8/finance/chart/BZ=F?interval=1d&range=2d';
    const r = await fetch(url, {
      headers: { 'User-Agent': 'Solvenin/1.0' },
      signal: AbortSignal.timeout(8000),
    });

    if (!r.ok) {
      return res.status(502).json({ error: `Yahoo returned ${r.status}` });
    }

    const d = await r.json();
    const meta = d?.chart?.result?.[0]?.meta;

    if (!meta?.regularMarketPrice) {
      return res.status(502).json({ error: 'No price in Yahoo response' });
    }

    const price = meta.regularMarketPrice;
    const prev = meta.chartPreviousClose;
    const change = prev
      ? ((price - prev) / prev * 100).toFixed(2)
      : null;

    return res.status(200).json({ price, change });
  } catch (e) {
    return res.status(502).json({ error: e.message || 'Fetch failed' });
  }
}
