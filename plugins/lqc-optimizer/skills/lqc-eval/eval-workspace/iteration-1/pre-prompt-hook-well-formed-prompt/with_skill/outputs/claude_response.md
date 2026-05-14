In `src/api/users.ts`, add a null guard at the top of the `getUser` function before the database lookup:

```typescript
async function getUser(userId: string | null): Promise<Response> {
  // Null guard — return 404 before hitting the database
  if (userId == null) {
    return new Response(JSON.stringify({ error: 'User not found' }), {
      status: 404,
      headers: { 'Content-Type': 'application/json' },
    });
  }

  // existing database lookup continues here (was line 47)
  const user = await db.users.findById(userId);
  // ...
}
```

The null guard uses `== null` to catch both `null` and `undefined`. The function signature is unchanged. The 404 response is returned before any database access occurs, so no TypeError can be thrown from a null `userId`.
