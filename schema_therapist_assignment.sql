-- ==============================================================================
-- ArtSpeak Schema Update: Caregiver Doctor/Therapist Selection & Assignment
-- ==============================================================================

-- 1. Add assigned_therapist_id column to children and session_reports
alter table public.children
  add column if not exists assigned_therapist_id uuid references public.therapists(id) on delete set null;

alter table public.session_reports
  add column if not exists assigned_therapist_id uuid references public.therapists(id) on delete set null;

create index if not exists idx_children_assigned_therapist on public.children(assigned_therapist_id);
create index if not exists idx_reports_assigned_therapist on public.session_reports(assigned_therapist_id);

-- 2. Allow authenticated caregivers to view the directory of registered therapists
drop policy if exists "Authenticated users can view registered therapists" on public.therapists;
create policy "Authenticated users can view registered therapists"
  on public.therapists for select to authenticated
  using (true);

-- 3. Ensure all registered therapists are verified so they can log in
update public.therapists set verified = true;

-- 4. Update auto_assign_therapist trigger to prioritize explicitly chosen therapist
create or replace function public.auto_assign_therapist()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  chosen_therapist uuid;
begin
  if new.needs_therapist = true then
    if new.assigned_therapist_id is not null then
      chosen_therapist := new.assigned_therapist_id;
    else
      select t.id into chosen_therapist
      from public.therapists t
      where t.verified = true
      order by (
        select count(*) from public.child_therapist_assignments a
        where a.therapist_id = t.id and a.active
      ) asc
      limit 1;
    end if;

    if chosen_therapist is not null then
      update public.child_therapist_assignments
      set active = false, ended_at = now()
      where child_id = new.id and active = true;

      insert into public.child_therapist_assignments (child_id, therapist_id, assigned_by, active)
      values (new.id, chosen_therapist, new.caregiver_id, true);
    end if;
  end if;
  return new;
end;
$$;

-- 5. Update set_report_routing trigger on session_reports to link report to assigned therapist
create or replace function public.set_report_routing()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_needs_therapist boolean;
  v_therapist_id uuid;
begin
  select c.needs_therapist, coalesce(c.assigned_therapist_id, cta.therapist_id)
  into v_needs_therapist, v_therapist_id
  from public.children c
  left join public.child_therapist_assignments cta on cta.child_id = c.id and cta.active = true
  where c.id = new.child_id;

  if v_needs_therapist then
    new.routed_to := 'therapist';
    new.assigned_therapist_id := v_therapist_id;
  else
    new.routed_to := 'caregiver';
  end if;

  return new;
end;
$$;

-- 6. Update RLS policy so ONLY the selected doctor/therapist can view reports routed to them
drop policy if exists "Therapists view reports routed to them" on public.session_reports;
create policy "Therapists view reports routed to them"
  on public.session_reports for select to authenticated
  using (
    routed_to = 'therapist'
    and (
      assigned_therapist_id = auth.uid()
      or child_id in (
        select cta.child_id from public.child_therapist_assignments cta
        where cta.therapist_id = auth.uid() and cta.active
      )
    )
  );

-- 7. Allow caregivers to update assignments for their children
drop policy if exists "Caregivers manage assignments for their children" on public.child_therapist_assignments;
create policy "Caregivers manage assignments for their children"
  on public.child_therapist_assignments for all to authenticated
  using (assigned_by = auth.uid())
  with check (assigned_by = auth.uid());

-- 8. Enforce child age limit between 4 and 13 years
alter table public.children drop constraint if exists children_age_check;
alter table public.children add constraint children_age_check check (age between 4 and 13);

