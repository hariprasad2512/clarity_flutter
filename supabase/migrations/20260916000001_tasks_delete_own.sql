-- Allow users to hard-delete their own tasks (delete propagation).
--
-- Why: swipe-delete removes the row locally and the sync push phase deletes
-- it from public.tasks so the next pull can't resurrect it on any device.
-- Without this policy the server delete is denied, the ID stays queued in
-- the delete outbox, and the task keeps coming back everywhere.
-- Run once via Supabase Dashboard → SQL Editor (idempotent; safe to re-run).
--
-- Applies to the shared Clarity database used by both clients.

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'tasks'
      and policyname = 'Users can delete own tasks'
  ) then
    create policy "Users can delete own tasks"
      on public.tasks for delete
      using (auth.uid() = user_id);
  end if;
end
$$;
