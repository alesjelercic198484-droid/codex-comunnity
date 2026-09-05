# CodeX Community – spletna stran + WL sistem

## Kaj vsebuje

- `index.html` – domača stran (landing page)
- `wl.html` + `wl.js` + `style.css` – WL (whitelist) sistem za prijave igralcev
- `server.js` – strežnik (čisti Node.js, brez zunanjih odvisnosti) in API
- `data/db.json` – podatkovna baza (uporabniki, seje, prijave) – **ni v Gitu** (ustvari se samodejno)

## Zagon

```bash
node server.js        # strežnik teče na http://0.0.0.0:8000
```

## Vloge in staff kode

| Vloga          | Kako pridobim                                             |
| -------------- | --------------------------------------------------------- |
| Igralec        | Registracija brez kode                                    |
| Moderator      | Ob registraciji vpiše staff kodo `CODEX-MOD-2026`         |
| Administrator  | Ob registraciji vpiše staff kodo `CODEX-ADMIN-2026`       |

Kode se spremenijo na vrhu datoteke `server.js` (`MODERATOR_CODE`, `ADMIN_CODE`).

## Pravila dostopa

- **Igralec**: vidi SAMO svoje prijave in njihov status (v obdelavi / odobreno / zavrnjeno) + opombo moderatorja.
- **Moderator / Administrator**: vidijo VSE prijavnice igralcev, jih odobrijo/zavrnejo z opombo.
- **Administrator**: poleg tega upravlja vloge vseh uporabnikov.
- Moderatorji ne morejo pregledovati svojih prijav; vsak ima največ eno prijavo hkrati v obdelavi.

## API

| Klic                              | Metoda | Dostop            | Opomba                       |
| --------------------------------- | ------ | ----------------- | ---------------------------- |
| `/api/register`                   | POST   | vsi               | `username, password, staffCode?` |
| `/api/login` / `/api/logout`      | POST   | vsi               | seja v piškotku (7 dni)      |
| `/api/me`                         | GET    | prijavljeni       | trenutni uporabnik           |
| `/api/applications`               | GET    | prijavljeni       | igralec: svoje, staff: vse   |
| `/api/applications`               | POST   | prijavljeni       | oddaja WL prijave            |
| `/api/applications/review`        | POST   | moderator/admin   | `id, status, note`           |
| `/api/users`                      | GET    | admin             | seznam uporabnikov           |
| `/api/users/role`                 | POST   | admin             | `id, role`                   |
