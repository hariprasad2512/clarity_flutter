-- Auto-bump `updated_at` on every UPDATE of public.tasks.
--
-- Why: cloud sync (Flutter + native macOS) resolves conflicts with
-- last-write-wins on `updated_at`. Without this trigger, edits made
-- outside the apps (Supabase Table Editor / SQL) leave `updated_at`
-- untouched, so merges can never see them as newer and the local row
-- wins forever. Run once via Supabase Dashboard → SQL Editor
-- (idempotent; safe to re-run).
--
-- Applies to the shared Clarity database used by both clients.

create or replace function public.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists tasks_touch_updated_at on public.tasks;

create trigger tasks_touch_updated_at
  before update on public.tasks
  for each row
  execute function public.touch_updated_at();
