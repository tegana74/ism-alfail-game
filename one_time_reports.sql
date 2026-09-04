-- ============================================================
-- رحلة اسم الفاعل — محاولات المراحل وتقارير الطلاب
-- شغّل هذا الملف مرة واحدة في Supabase SQL Editor
-- ============================================================

create table if not exists public.stage_attempts (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references public.profiles(id) on delete cascade,
  stage_id bigint not null references public.stages(id) on delete cascade,
  attempt_no integer not null,
  status text not null default 'active' check (status in ('active','completed','abandoned')),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  score_earned integer not null default 0,
  stars_earned integer not null default 0,
  created_at timestamptz not null default now(),
  unique(player_id, stage_id, attempt_no)
);

create index if not exists idx_stage_attempts_player on public.stage_attempts(player_id);
create index if not exists idx_stage_attempts_stage on public.stage_attempts(stage_id);
create index if not exists idx_stage_attempts_player_stage on public.stage_attempts(player_id, stage_id);

alter table public.stage_access
  add column if not exists max_attempts integer not null default 1;

alter table public.stage_access
  add column if not exists attempts_used integer not null default 0;

-- Existing paid/manual access grants are one-time by default.
update public.stage_access
set max_attempts = 1
where max_attempts is null or max_attempts < 1;

update public.stage_access sa
set attempts_used = least(
  greatest(0, sa.attempts_used),
  greatest(1, sa.max_attempts)
);

-- Fix the old player_answers uniqueness: one attempt may contain many questions.
alter table public.player_answers
  drop constraint if exists player_answers_attempt_id_key;

alter table public.player_answers
  drop constraint if exists player_answers_attempt_question_key;

alter table public.player_answers
  add constraint player_answers_attempt_question_key unique (attempt_id, question_id);

alter table public.stage_attempts enable row level security;

revoke all on table public.stage_attempts from anon, authenticated;
grant select on table public.stage_attempts to authenticated;

drop policy if exists "stage_attempts_self_read" on public.stage_attempts;
create policy "stage_attempts_self_read"
on public.stage_attempts
for select to authenticated
using ((select auth.uid()) = player_id);

drop policy if exists "admin_stage_attempts_all" on public.stage_attempts;
create policy "admin_stage_attempts_all"
on public.stage_attempts
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Admin needs to read detailed answer rows.
drop policy if exists "admin_player_answers_all" on public.player_answers;
create policy "admin_player_answers_all"
on public.player_answers
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Start or resume a stage attempt.
create or replace function public.start_stage_attempt(p_stage_id bigint)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_stage public.stages%rowtype;
  v_access public.stage_access%rowtype;
  v_attempt public.stage_attempts%rowtype;
  v_no integer;
begin
  if v_uid is null then
    raise exception 'يجب تسجيل الدخول';
  end if;

  select * into v_stage
  from public.stages
  where id = p_stage_id and is_active = true;

  if not found then raise exception 'المرحلة غير موجودة'; end if;

  -- Resume an already active attempt rather than creating another one.
  select * into v_attempt
  from public.stage_attempts
  where player_id = v_uid and stage_id = p_stage_id and status = 'active'
  order by started_at desc
  limit 1;

  if found then
    return jsonb_build_object(
      'allowed', true,
      'attempt_id', v_attempt.id,
      'attempt_no', v_attempt.attempt_no,
      'resumed', true
    );
  end if;

  -- Admin can test any stage without consuming a student's one-time access.
  if public.is_admin() then
    select coalesce(max(attempt_no),0) + 1 into v_no
    from public.stage_attempts where player_id=v_uid and stage_id=p_stage_id;
  else
    if v_stage.is_free then
      select coalesce(max(attempt_no),0) + 1 into v_no
      from public.stage_attempts where player_id=v_uid and stage_id=p_stage_id;
    else
      select * into v_access
      from public.stage_access
      where player_id=v_uid and stage_id=p_stage_id
      for update;

      if not found then
        raise exception 'هذه المرحلة مغلقة. يلزم موافقة المدير أو الدفع.';
      end if;

      if v_access.attempts_used >= v_access.max_attempts then
        raise exception 'تم استخدام المحاولة المسموح بها لهذه المرحلة. يلزم موافقة المدير لإعادة الحل.';
      end if;

      update public.stage_access
      set attempts_used = attempts_used + 1
      where id = v_access.id;

      select coalesce(max(attempt_no),0) + 1 into v_no
      from public.stage_attempts where player_id=v_uid and stage_id=p_stage_id;
    end if;
  end if;

  insert into public.stage_attempts(player_id,stage_id,attempt_no,status)
  values (v_uid,p_stage_id,v_no,'active')
  returning * into v_attempt;

  return jsonb_build_object(
    'allowed', true,
    'attempt_id', v_attempt.id,
    'attempt_no', v_attempt.attempt_no,
    'resumed', false
  );
end;
$$;

revoke all on function public.start_stage_attempt(bigint) from public;
grant execute on function public.start_stage_attempt(bigint) to authenticated;

-- Finish a stage and calculate its score from the recorded answers.
create or replace function public.finish_stage_attempt(p_attempt_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_attempt public.stage_attempts%rowtype;
  v_score integer := 0;
  v_stars integer := 0;
begin
  if v_uid is null then raise exception 'يجب تسجيل الدخول'; end if;

  select * into v_attempt
  from public.stage_attempts
  where id=p_attempt_id and player_id=v_uid
  for update;

  if not found then raise exception 'المحاولة غير موجودة'; end if;

  if v_attempt.status = 'completed' then
    return jsonb_build_object('ok',true,'already_completed',true,'score_earned',v_attempt.score_earned,'stars_earned',v_attempt.stars_earned);
  end if;

  select coalesce(sum(points),0),
         coalesce(sum(case when points=2 then 2 when points=1 then 1 else 0 end),0)
  into v_score, v_stars
  from public.player_answers
  where attempt_id=p_attempt_id and player_id=v_uid;

  update public.stage_attempts
  set status='completed', completed_at=now(), score_earned=v_score, stars_earned=v_stars
  where id=p_attempt_id;

  update public.player_stage_progress p
  set current_question=0,
      best_score=greatest(coalesce(p.best_score,0),v_score),
      stars=greatest(coalesce(p.stars,0),v_stars),
      completed=true,
      updated_at=now()
  where p.player_id=v_uid and p.stage_id=v_attempt.stage_id;

  return jsonb_build_object('ok',true,'already_completed',false,'score_earned',v_score,'stars_earned',v_stars);
end;
$$;

revoke all on function public.finish_stage_attempt(uuid) from public;
grant execute on function public.finish_stage_attempt(uuid) to authenticated;

-- Replace the answer function with attempt validation and per-question uniqueness.
create or replace function public.record_game_answer(
  p_attempt_id uuid,
  p_question_id bigint,
  p_selected_choice char(1),
  p_elapsed_seconds numeric
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_q public.questions%rowtype;
  v_stage public.stages%rowtype;
  v_attempt public.stage_attempts%rowtype;
  v_correct boolean := false;
  v_points integer := 0;
  v_old_score integer := 0;
  v_old_stars integer := 0;
  v_old_coins integer := 0;
  v_inserted boolean := false;
begin
  if v_uid is null then raise exception 'يجب تسجيل الدخول'; end if;
  if p_attempt_id is null then raise exception 'رقم المحاولة غير صحيح'; end if;
  if p_elapsed_seconds is null or p_elapsed_seconds < 0 then raise exception 'زمن الإجابة غير صحيح'; end if;

  select * into v_attempt
  from public.stage_attempts
  where id=p_attempt_id and player_id=v_uid and status='active';
  if not found then raise exception 'المحاولة غير صالحة أو انتهت'; end if;

  select * into v_q
  from public.questions
  where id=p_question_id and stage_id=v_attempt.stage_id and is_active=true;
  if not found then raise exception 'السؤال غير موجود داخل هذه المرحلة'; end if;

  select * into v_stage
  from public.stages
  where id=v_attempt.stage_id and is_active=true;
  if not found then raise exception 'المرحلة غير موجودة'; end if;

  if p_elapsed_seconds < v_stage.time_limit_seconds then
    v_correct := lower(coalesce(p_selected_choice,'')) = lower(v_q.correct_choice);
    if v_correct then
      v_points := case when p_elapsed_seconds <= 30 then 2 else 1 end;
    end if;
  end if;

  insert into public.player_answers(
    attempt_id, player_id, question_id, selected_choice,
    is_correct, points, elapsed_seconds
  ) values (
    p_attempt_id, v_uid, p_question_id,
    case when p_selected_choice is null then null else lower(p_selected_choice) end,
    v_correct, v_points, p_elapsed_seconds
  )
  on conflict (attempt_id, question_id) do nothing;

  v_inserted := found;
  if not v_inserted then
    return jsonb_build_object('duplicate',true,'points',0,'correct',false);
  end if;

  select total_score,total_stars,coins
  into v_old_score,v_old_stars,v_old_coins
  from public.profiles
  where id=v_uid
  for update;

  if not found then raise exception 'ملف اللاعب غير موجود'; end if;

  update public.profiles
  set total_score=coalesce(total_score,0)+v_points,
      total_stars=coalesce(total_stars,0)+case when v_points=2 then 2 when v_points=1 then 1 else 0 end,
      coins=coalesce(coins,0)+case when v_points=2 then 2 when v_points=1 then 1 else 0 end
  where id=v_uid;

  return jsonb_build_object(
    'duplicate',false,
    'correct',v_correct,
    'points',v_points,
    'elapsed',p_elapsed_seconds,
    'time_limit',v_stage.time_limit_seconds,
    'score',v_old_score+v_points,
    'stars',v_old_stars+case when v_points=2 then 2 when v_points=1 then 1 else 0 end,
    'coins',v_old_coins+case when v_points=2 then 2 when v_points=1 then 1 else 0 end
  );
end;
$$;

revoke all on function public.record_game_answer(uuid,bigint,char,numeric) from public;
grant execute on function public.record_game_answer(uuid,bigint,char,numeric) to authenticated;

-- Admin can inspect access usage.
drop policy if exists "admin_stage_access_all" on public.stage_access;
create policy "admin_stage_access_all"
on public.stage_access
for all to authenticated
using (public.is_admin())
with check (public.is_admin());

-- Player can create/read access only for themselves; admin policy above supersedes for admin users.
drop policy if exists "access_self_read" on public.stage_access;
create policy "access_self_read"
on public.stage_access
for select to authenticated
using ((select auth.uid()) = player_id);

-- Table grants are needed by the API role; RLS policies below prevent
-- normal students from inserting/updating/deleting access rows.
grant select, insert, update, delete on table public.stage_access to authenticated;

-- Students only need to read their own answer history; admins get select through the admin policy.
grant select on table public.player_answers to authenticated;

-- Students only need to read their own attempts; attempts are created/updated through RPCs.
grant select on table public.stage_attempts to authenticated;

-- Student can still read their own answer history.
drop policy if exists "answers_self_read" on public.player_answers;
create policy "answers_self_read"
on public.player_answers
for select to authenticated
using ((select auth.uid()) = player_id);
