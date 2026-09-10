-- Migration: Add missing RLS policies for `users` table
-- 
-- The schema enables RLS on `users` but only had a SELECT policy.
-- Without INSERT and UPDATE policies, authenticated users could not
-- create or update their own profile row, causing 403 errors on sign-up
-- and profile updates.

-- Allow a newly-signed-up user to create their own row.
-- The check ensures they can only insert a row pointing to their own
-- auth.uid() — they cannot create rows for other users.
create policy "users_insert_own" on users
  for insert
  with check (auth_user_id = auth.uid());

-- Allow a user to update their own row (e.g. linking fpl_manager_id,
-- updating display_name). They cannot change auth_user_id (it stays
-- fixed), and they cannot touch other users' rows.
create policy "users_update_own" on users
  for update
  using (auth_user_id = auth.uid())
  with check (auth_user_id = auth.uid());
