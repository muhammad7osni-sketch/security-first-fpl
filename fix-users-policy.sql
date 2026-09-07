-- Fix users table RLS policy to allow UPDATE
-- Run this in Supabase SQL Editor

-- Drop existing policy
DROP POLICY IF EXISTS "users_select_own" ON users;

-- Create new policies for SELECT and UPDATE
CREATE POLICY "users_select_own" ON users
  FOR SELECT USING (auth_user_id = auth.uid());

CREATE POLICY "users_update_own" ON users
  FOR UPDATE USING (auth_user_id = auth.uid());

CREATE POLICY "users_insert_own" ON users
  FOR INSERT WITH CHECK (auth_user_id = auth.uid());
