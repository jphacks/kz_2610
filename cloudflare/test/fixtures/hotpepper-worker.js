import { findRestaurantPhoto } from "../../src/hotpepper.js";

// Synthetic key and mocked upstream only. Exercises workerd's actual fetch API.
export default {
  async fetch(request) {
    try {
      const photo = await findRestaurantPhoto(
        await request.json(),
        "synthetic-runtime-fixture",
      );
      return Response.json({ photo });
    } catch {
      return Response.json({ error: "photo_unavailable" }, { status: 502 });
    }
  },
};
