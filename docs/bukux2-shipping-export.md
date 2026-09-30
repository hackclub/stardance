# One-time BukuX2 shipping-address export

Deploy the job code only. **Never commit, bake into an image, paste into a console,
or attach to CI the input CSV or the address export.** This job has no schedule,
HTTP endpoint, migration, or database writes. Use it only for authorized event
fulfillment, and delete private copies when no longer needed.

The contributor CSV has `user_id`, `username`, `slack_id`, `counted_ships`, and
`approved_hours` columns, not emails. The job matches the stable `user_id` against
the production database and uses that user's existing HCA OAuth token. It exports
their current Stardance email and current HCA postal address, not a historical
address or a global HCA email lookup. It never recalculates eligibility or adds
people outside the CSV. Repeated IDs are exported once.

## Run from the production app container

1. Create a temporary directory **outside the application checkout**, owned by
   the app's operating-system user, with mode `700` (for example, use
   `mktemp -d /tmp/bukux2-shipping.XXXXXX` as that user).
2. Transfer the CSV over an authenticated private channel to the host, then
   copy it into that directory in the running app container. Set the input file
   to mode `600` and ensure the app user owns it. Do not upload it to a public
   bucket or repository. The input may also be reduced locally to a CSV containing
   only its `user_id` column; the other columns are not used.
3. Set `BUKUX2_INPUT` to the private input path and `BUKUX2_OUTPUT` to a new path
   in the same private directory, such as `dry-run.csv`. Then run:

   ```sh
   bin/rails runner 'p OneTime::ExportBukuX2ShippingAddressesJob.perform_now(input_path: ENV.fetch("BUKUX2_INPUT"), output_path: ENV.fetch("BUKUX2_OUTPUT"))'
   ```

   The default is a dry run: it checks users, linked identities and stored tokens
   **without contacting HCA**. It returns counts only. `ready` does not establish
   that a token is valid or has address access.
4. Point `BUKUX2_OUTPUT` at a different, unused path, such as `addresses.csv`, then
   explicitly fetch addresses:

   ```sh
   bin/rails runner 'p OneTime::ExportBukuX2ShippingAddressesJob.perform_now(input_path: ENV.fetch("BUKUX2_INPUT"), output_path: ENV.fetch("BUKUX2_OUTPUT"), dry_run: false)'
   ```

   Use **perform_now**, not `perform_later`: the input and output exist only on
   this container. Requests are sequential, spaced by 200 ms, with 5-second
   connection and 15-second request timeouts. An export of 474 people takes at
   least about 95 seconds plus request time. Keep the runner connected until it
   reports completion. No automatic retries or OAuth-token changes are made.
5. Download the result privately. Review statuses before using it for fulfillment.
   Import postal codes as text to preserve leading zeroes. Output files are
   owner-only (`600`); existing files are never overwritten. If the runner aborts,
   treat the output as incomplete and rerun to a new filename.
6. Remove the input, dry-run report, output and any host transfer copies after
   securely collecting the result. Container temporary storage is not a backup.

## Results and review

The CSV includes `user_id`, `email`, `status`, `address_count`, `first_name`,
`last_name`, `line_1`, `line_2`, `city`, `state`, `postal_code`, `country`.
No tokens, birthdays, phone numbers or raw HCA responses are exported. Logs include
only the job ID and aggregate counts, not participant rows or exception details.

- `ok`: one address, or exactly one explicitly primary address. This is not postal
  deliverability validation; review the result before shipping.
- `multiple_addresses`: no unambiguous primary; address fields are left blank.
- `incomplete_address`: selected address lacks a street line or country; review it.
- `user_not_found`, `no_hca_identity`, `no_access_token`: account cannot be queried.
- `address_field_unavailable`: HCA omitted addresses; token scope may be missing.
- `no_address`: HCA supplied no addresses.
- `http_401` / `http_403`: authorization failed; the person may need to reconnect
  with the address scope. The job does not refresh or broaden access.
- `http_429`, `http_5xx`, `request_failed`: rate limit or transient error; later rerun
  a private CSV containing only failed user IDs, using a fresh output filename.
- `invalid_response`: unexpected or malformed HCA data; review before retrying.

No background deployment hook runs this job. A human must explicitly invoke it.
