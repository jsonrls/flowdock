# Flowdock launch site

A dependency-free static landing page for the Flowdock launch list.

## Preview locally

From the repository root:

```sh
python3 -m http.server 8080
```

Then visit `http://localhost:8080/web/`.

## Connect the waitlist

The signup form works in local/demo mode out of the box and stores submissions in the browser's
`localStorage`. To collect signups from a deployed site, set the form's `data-endpoint` in
`index.html` to an HTTPS endpoint that accepts a JSON `POST` body shaped like this:

```json
{
  "email": "person@example.com",
  "source": "flowdock-launch-site"
}
```

Any successful `2xx` response is treated as a completed signup.
