# `/flash-sales` — the endpoint this section wants

The app ships a flash sale section today, but the backend has no flash sale.
This is the contract that would replace the stand-in.

## Why this document exists

`GET /api/v1/flash-sales` returns 404. The only time-limited promotion the
backend models is four columns on a `hero_banners` row:

| Column | Live value on all 12 banners |
|---|---|
| `promo_code` | `null` |
| `promo_headline_percent` | `null` |
| `promo_amount` | `null` |
| `promo_valid_until` | `null` |

Nothing in the catalogue carries a list price, a discount, a stock level or a
sold count — `/feed/discover` rows have `display_price` and nothing to compare
it against.

So the section currently assembles a sale from a banner's promo fields plus the
discover feed, and invents the rest in
`lib/features/flash_sale/data/flash_sale_placeholder.dart`. **The invented part
includes the struck-through "was" price**, which is a savings claim that is not
true. That file has one `enabled` flag; turning it off makes the section honest
and mostly empty. Implementing what follows is what makes it both honest and
full.

## Two ways to land this

**The cheap one — no new endpoint.** Populate the four `hero_banners` promo
columns on one active banner. The app already parses all four
(`HeroBanner.headlinePercent`, `.promoAmount`, `.promoCode`, `.validUntil`) and
`FlashSaleRepository` already prefers them over the stand-in. A real
`promo_headline_percent` makes the discount badge and the struck price genuine,
because the catalogue price becomes a true "before". Still no stock or sold
figures — those cards would simply omit the meter, which they already handle.

**The full one — the endpoint below.** Needed for per-product discounts, stock
and sold counts, and for more than one sale at a time.

## `GET /api/v1/flash-sales`

Public, no credential — same as `/feed/discover` and `/hero-banners`, and the
app calls it with `skipAuth`.

Returns the sales that are running or about to, soonest deadline first. An
empty array is the normal answer and the app renders nothing for it.

```json
[
  {
    "id": "6f2c1e7a-…",
    "headline": "Flash Sale",
    "subhead": "Unbeatable deals. Limited stock.",
    "starts_at": "2026-08-25T12:00:00Z",
    "ends_at": "2026-08-25T18:00:00Z",
    "headline_percent": 40,
    "promo_code": "FLASH40",
    "items": [
      {
        "num_iid": "692448816398",
        "sale_price": 2999,
        "list_price": 4999,
        "discount_percent": 40,
        "stock": 36,
        "sold_percent": 64
      }
    ]
  }
]
```

### Fields

| Field | Type | Required | Notes |
|---|---|---|---|
| `id` | string | ✓ | Stable across the sale's life. |
| `headline` | string | ✓ | |
| `subhead` | string\|null | | |
| `starts_at` | RFC 3339 | | Omit or null for "already running". |
| `ends_at` | **RFC 3339, UTC, with offset** | ✓ | See the note below — this is the one that goes wrong. |
| `headline_percent` | int\|null | | Campaign-wide discount. |
| `promo_code` | string\|null | | |
| `items[].num_iid` | string | ✓ | The catalogue key, **not** the numeric `id`. |
| `items[].sale_price` | number | ✓ | Rupees, what is charged now. |
| `items[].list_price` | number\|null | | Rupees, the real price outside the sale. **Send null rather than a guess** — the app strikes this through, and a fabricated one is a false savings claim. |
| `items[].discount_percent` | int\|null | | Omit and the app derives it from the two prices. |
| `items[].stock` | int\|null | | Units left. Null hides the meter. |
| `items[].sold_percent` | int 0–100\|null | | Null hides the bar. |

### `ends_at` must carry a timezone

The countdown is the whole feature and it is computed against the device clock.
A naive `"2026-08-25T18:00:00"` is parsed as *local* time, so a shopper in
Kathmandu (UTC+5:45) and the server disagree by five and three quarter hours —
the sale ends early for some people and late for others, and nobody can
reproduce it. Send `Z` or an explicit offset.

The app is already lenient here (`asDate` in `lib/core/network/json.dart` calls
`DateTime.tryParse` then `.toLocal()`), which means a missing offset fails
quietly rather than loudly. That is exactly why it needs saying.

### Prices are rupees, VAT included

Everything the shopper sees in this app is VAT-inclusive; the checkout
back-solves the 13% for display. `sale_price` and `list_price` must follow the
same rule as `display_price`, or the cart total will not match the card.

### An ended sale

Return it with a past `ends_at`, or drop it — the app handles both. It shows
"This flash sale has ended" and stops advertising the prices, and a
pull-to-refresh picks up whatever is next.

Do **not** extend `ends_at` on a live sale to keep it running. The countdown
recomputes from the wall clock on every tick, so the number visibly jumps, and a
deadline that moves is the one thing that makes a countdown untrustworthy.

## What the app does when this lands

`FlashSaleRepository.current()` is the only place to change: read this endpoint
instead of composing a sale from banners and the discover feed, and delete the
`flash_sale_placeholder.dart` import. `FlashSale` and `FlashSaleItem` already
have exactly these fields, and every element on the card is already conditional
on its figure being non-null — so a payload with no `stock` renders a finished
card rather than a broken one.
