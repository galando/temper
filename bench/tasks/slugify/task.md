Add a `slugify(text)` function to `src/textutil.py`. It turns a title into a URL slug:

- lowercase everything
- accented Latin letters become their plain ASCII letter (é becomes e, ü becomes u, ñ becomes n)
- every run of characters that are not a to z or 0 to 9 becomes a single `-`
- no `-` at the start or the end
- an input with nothing usable returns an empty string

Then use it in `src/posts.py`: `create_post` must store the slug of the title in the post's `slug` field.
