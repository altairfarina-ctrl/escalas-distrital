-- ============================================================================
--  ESCALAS DISTRITAL – Etapa 2 (Supabase) · schema do banco
--  Data: 07/10 · Decide pelo usuário: banco NASCE LIMPO (só estrutura base)
--          + botão opcional "carregar dados de demonstração" (vem depois)
--          + login por USUÁRIO + SENHA (e-mail sintético por baixo)
--
--  COMO USAR:
--   1) Supabase → projeto aberto → menu esquerdo "SQL Editor" → "New query"
--   2) Cole ESTE ARQUIVO inteiro
--   3) Clique em "Run" (ou Ctrl+Enter) – tem que terminar sem erro
--   4) Depois: Table Editor deve mostrar as 6 tabelas abaixo
--
--  ANTES DE RODAR (configuração de login, 30 segundos):
--   Authentication → Sign In / Providers → Email → desmarque
--   "Confirm email" (o sistema cria o usuário já confirmado, sem e-mail).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1) IGREJAS  (7 do distrito, com cidade)
-- ---------------------------------------------------------------------------
create table if not exists churches (
  id         uuid primary key default gen_random_uuid(),
  name       text not null unique,                     -- 'IASD Ivailândia'
  city       text not null default 'Distrito · ANP',   -- aparece nos cartões
  ordem      int  not null default 0,
  ativa      boolean not null default true,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 2) AGENDAS  (decisão do usuário 07/10: agenda normal vale SÓ na igreja onde
--    foi criada, igual ao protótipo; Pastoral/Associação não têm dona
--    (church_id nulo) e valem para TODAS as igrejas)
--    tipo: 'normal' (igreja) · 'pastoral' e 'associacao' (só Admin Distrital)
-- ---------------------------------------------------------------------------
create table if not exists departments (
  id       text primary key,                  -- 'louvor' · 'louvor-a1b2c3d4' (1 por igreja)
  key      text not null,                     -- 'louvor' (a mesma key em todas as igrejas)
  church_id uuid references churches(id) on delete cascade,  -- null = agenda do distrito
  name   text not null,                       -- 'Louvor'
  color  text not null default '#888888',
  sigla  text not null default '',            -- 'Louv' (prefixo da pill)
  tooltip text not null default '',           -- tooltip completo ('full' é palavra reservada do Postgres)
  tipo   text not null default 'normal'
         check (tipo in ('normal','pastoral','associacao')),
  ordem  int  not null default 0,
  ativa  boolean not null default true
);
-- a mesma key não se repete dentro da mesma igreja (as distritais valem só 1 vez)
create unique index if not exists depts_key_igreja
  on departments (key, coalesce(church_id, '00000000-0000-0000-0000-000000000001'::uuid));

-- ---------------------------------------------------------------------------
-- 3) USUÁRIOS  (vínculo com o Supabase Auth)
--    login   = o apelido que ele digita (mantido como o usuário pediu)
--    auth_id = id do Supabase Auth; o e-mail real é `login@escalas.distrital.app`
--              (fictício, ninguém vê – por isso senha esquecida é só pelo admin)
--    igreja  = null significa "distrital" (vai em todas, como hoje o '*')
--    dep     = agendas que ele LIDERA (só do nível 'membro')
-- ---------------------------------------------------------------------------
create table if not exists users (
  id        uuid primary key default gen_random_uuid(),
  auth_id   uuid unique references auth.users(id) on delete set null,
  login     text not null,
  nome      text not null,
  zap       text not null default '',
  nivel     text not null default 'visitante'
            check (nivel in ('visitante','membro','admin_local','admin_dist')),
  church_id uuid references churches(id) on delete cascade,
  dep       text[] not null default '{}',
  ativo     boolean not null default true,
  created_at timestamptz not null default now()
);
-- login repetido só vale em OUTRA igreja (igual ao protótipo)
create unique index if not exists users_login_igreja
  on users (login, coalesce(church_id, '00000000-0000-0000-0000-000000000001'::uuid));

-- ---------------------------------------------------------------------------
-- 4) ESCALAS
--    distrital = true nas agendas Pastoral/Associação (valem em todas as igrejas)
-- ---------------------------------------------------------------------------
create table if not exists events (
  id            bigint generated always as identity primary key,
  church_id     uuid not null references churches(id) on delete cascade,
  department_id text not null references departments(id),
  dia           date not null,                     -- '2026-10-04'
  texto         text not null,
  distrital     boolean not null default false,
  created_by    uuid references users(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists events_church_dia on events (church_id, dia);
create index if not exists events_dia        on events (dia);

-- ---------------------------------------------------------------------------
-- 5) LISTA DE OFICIAIS  (linhas {d,c,r} + anexo em PDF, por igreja)
--    Guardado como JSON de propósito: o app trata a lista como um bloco só.
--    Se o PDF passar de ~1 MB, migramos o anexo para o Storage (bucket 'anexos').
-- ---------------------------------------------------------------------------
create table if not exists officers (
  church_id  uuid primary key references churches(id) on delete cascade,
  linhas     jsonb not null default '[]'::jsonb,   -- [{d:'…', c:'…', r:'…'}]
  pdf_nome   text,
  pdf_dados  text,                                 -- PDF em base64
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 6) PROGRAMAÇÃO  (títulos + itens, por igreja)
-- ---------------------------------------------------------------------------
create table if not exists programs (
  church_id  uuid primary key references churches(id) on delete cascade,
  dados      jsonb not null default '[]'::jsonb,
            -- [{t:'Culto de Domingo', dia:'Domingo', data:'', obs:'',
            --   itens:[{h:'07h30', a:'Louvores', r:''}]}]
  updated_at timestamptz not null default now()
);

-- ===========================================================================
--  FUNÇÕES AUXILIARES (as regras de permissão usam estas)
--  'security definer' = lê a tabela users sem entrar em laço com o RLS
-- ===========================================================================
create or replace function meu_nivel() returns text
language sql stable security definer set search_path = public as $$
  select coalesce((select nivel from users where auth_id = auth.uid() and ativo), 'visitante');
$$;

create or replace function minha_igreja() returns uuid
language sql stable security definer set search_path = public as $$
  select (select church_id from users where auth_id = auth.uid());
$$;

create or replace function minhas_agendas() returns text[]
language sql stable security definer set search_path = public as $$
  select coalesce((select dep from users where auth_id = auth.uid()), '{}');
$$;

create or replace function e_admin() returns boolean
language sql stable as $$
  select meu_nivel() in ('admin_local','admin_dist');
$$;

-- EDIÇÃO de uma escala na agenda (espelha canEdit() do protótipo)
--  · Admin Distrital: qualquer agenda, em qualquer igreja
--  · Admin Local: só as agendas da PRÓPRIA igreja (as distritais não têm dona → bloqueia)
--  · Membro (Líder): só as agendas do array `dep` dele e só na própria igreja
--  · Membro comum / visitante: nunca
create or replace function pode_editar(dep text) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when meu_nivel() = 'admin_dist' then true
    when meu_nivel() = 'admin_local' then
         exists(select 1 from departments d
                 where d.id = dep and d.church_id = minha_igreja())
    when meu_nivel() = 'membro' then
         dep = any (minhas_agendas())
         and exists(select 1 from departments d
                     where d.id = dep and d.church_id = minha_igreja())
    else false
  end;
$$;

-- mexer na LINHA da agenda no ⚙ Gerenciar agendas (alterar/excluir)
--  · Admin Distrital: qualquer uma (inclusive as do distrito)
--  · Admin Local: só as da própria igreja
create or replace function pode_mexer_agenda(dep text) returns boolean
language sql stable security definer set search_path = public as $$
  select case
    when meu_nivel() = 'admin_dist' then true
    when meu_nivel() = 'admin_local' then
         exists(select 1 from departments d
                 where d.id = dep and d.church_id = minha_igreja())
    else false
  end;
$$;

-- ===========================================================================
--  RLS – nada é visível/gravável sem passar pelas regras acima
--  (os "drop policy if exists" deixam este arquivo rodável mais de 1x)
-- ===========================================================================
alter table churches    enable row level security;
alter table departments enable row level security;
alter table users       enable row level security;
alter table events      enable row level security;
alter table officers    enable row level security;
alter table programs    enable row level security;

drop policy if exists churches_sel on churches;
drop policy if exists churches_ins on churches;
drop policy if exists churches_upd on churches;
drop policy if exists churches_del on churches;
drop policy if exists depts_sel    on departments;
drop policy if exists depts_ins    on departments;
drop policy if exists depts_upd    on departments;
drop policy if exists depts_del    on departments;
drop policy if exists users_sel    on users;
drop policy if exists users_ins    on users;
drop policy if exists users_upd    on users;
drop policy if exists users_del    on users;
drop policy if exists events_sel   on events;
drop policy if exists events_ins   on events;
drop policy if exists events_upd   on events;
drop policy if exists events_del   on events;
drop policy if exists officers_sel on officers;
drop policy if exists officers_wr  on officers;
drop policy if exists officers_upd on officers;
drop policy if exists programs_sel on programs;
drop policy if exists programs_wr  on programs;
drop policy if exists programs_upd on programs;

-- igrejas: todo logado vê; só admin mexe; só distrital apaga
create policy churches_sel on churches for select to authenticated using (true);
create policy churches_ins on churches for insert to authenticated with check (e_admin());
create policy churches_upd on churches for update to authenticated using (e_admin());
create policy churches_del on churches for delete to authenticated using (meu_nivel() = 'admin_dist');

-- agendas: vê as da própria igreja + as do distritais (sem dona); mexem só admins
create policy depts_sel on departments for select to authenticated
  using ( meu_nivel() = 'admin_dist'
       or church_id is null            -- agenda do distrito (Pastoral/Associação)
       or church_id = minha_igreja() );
-- criar: Admin Distrital em qualquer igreja (ou distrital sem dona); Admin Local só na sua
create policy depts_ins on departments for insert to authenticated
  with check ( case
    when meu_nivel() = 'admin_dist' then true
    when meu_nivel() = 'admin_local' then church_id = minha_igreja()
    else false end );
create policy depts_upd on departments for update to authenticated
  using ( pode_mexer_agenda(id) ) with check ( pode_mexer_agenda(id) );
create policy depts_del on departments for delete to authenticated
  using ( pode_mexer_agenda(id) );

-- usuários: cada um vê os da própria igreja (e SEMPRE o próprio cadastro);
--           só o Admin Distrital vê/mexe em TUDO; o Admin Local só na IGREJA DELE
create policy users_sel on users for select to authenticated
  using ( auth_id = auth.uid()
       or meu_nivel() = 'admin_dist'
       or church_id = minha_igreja() );
create policy users_ins on users for insert to authenticated
  with check ( case
    when meu_nivel() = 'admin_dist' then true
    when meu_nivel() = 'admin_local' then church_id = minha_igreja()
    else false end );
create policy users_upd on users for update to authenticated
  using ( case
    when meu_nivel() = 'admin_dist' then true
    when meu_nivel() = 'admin_local' then church_id = minha_igreja()
    else false end )
  with check ( case
    when meu_nivel() = 'admin_dist' then true
    when meu_nivel() = 'admin_local' then church_id = minha_igreja()
    else false end );
create policy users_del on users for delete to authenticated
  using ( case
    when meu_nivel() = 'admin_dist' then true
    when meu_nivel() = 'admin_local' then church_id = minha_igreja()
    else false end );

-- escalas: vê da própria igreja + as do distrito; grava só se editar a agenda
create policy events_sel on events for select to authenticated
  using ( meu_nivel() = 'admin_dist'
       or distrital
       or church_id = minha_igreja() );
create policy events_ins on events for insert to authenticated
  with check ( pode_editar(department_id)
       and ( meu_nivel() = 'admin_dist' or church_id = minha_igreja() ) );
create policy events_upd on events for update to authenticated
  using ( pode_editar(department_id)
       and ( meu_nivel() = 'admin_dist' or church_id = minha_igreja() ) );
create policy events_del on events for delete to authenticated
  using ( pode_editar(department_id)
       and ( meu_nivel() = 'admin_dist' or church_id = minha_igreja() ) );

-- oficiais / programação: leitura da própria igreja (distrital vê tudo)
create policy officers_sel on officers for select to authenticated
  using ( meu_nivel() = 'admin_dist' or church_id = minha_igreja() );
create policy officers_wr on officers for insert to authenticated
  with check ( e_admin() and ( meu_nivel() = 'admin_dist' or church_id = minha_igreja() ) );
create policy officers_upd on officers for update to authenticated
  using ( e_admin() and ( meu_nivel() = 'admin_dist' or church_id = minha_igreja() ) );

create policy programs_sel on programs for select to authenticated
  using ( meu_nivel() = 'admin_dist' or church_id = minha_igreja() );
create policy programs_wr on programs for insert to authenticated
  with check ( e_admin() and ( meu_nivel() = 'admin_dist' or church_id = minha_igreja() ) );
create policy programs_upd on programs for update to authenticated
  using ( e_admin() and ( meu_nivel() = 'admin_dist' or church_id = minha_igreja() ) );

-- permissões de acesso via API
grant usage on schema public to anon, authenticated;
grant all on all tables in schema public to anon, authenticated;
alter default privileges in schema public grant all on tables to anon, authenticated;

-- ===========================================================================
--  ESTRUTURA BASE (aprovada: 7 igrejas + as agendas) – não é dado de teste
--  · as 2 agendas do distrito (ANP e Pr. Erivando) são 1 linha só, sem igreja
--  · as 7 normais são copiadas para CADA igreja (cada uma edita a sua)
-- ===========================================================================
insert into churches (name, city, ordem) values
  ('IASD Barbosa Ferraz',     'Distrito · ANP', 1),
  ('IASD Engenheiro Beltrão', 'Distrito · ANP', 2),
  ('IASD Floresta',           'Distrito · ANP', 3),
  ('IASD Itambé',             'Distrito · ANP', 4),
  ('IASD Ivailândia',         'Distrito · ANP', 5),
  ('IASD Jardim Kakimori',    'Distrito · ANP', 6),
  ('IASD Quinta do Sol',      'Distrito · ANP', 7)
on conflict (name) do nothing;

-- agendas do distrito (church_id nulo = valem em TODAS as igrejas)
insert into departments (id, key, church_id, name, color, sigla, tooltip, tipo, ordem) values
  ('anp',   'anp',   null, 'ANP',          '#FF5CA8', 'ANP', 'ANP - Associação Norte Paranaense', 'associacao', 8),
  ('past1', 'past1', null, 'Pr. Erivando', '#E879F9', 'PrE', 'Agenda Pastoral - Pr. Erivando',    'pastoral',   9)
on conflict (id) do nothing;

-- agendas normais: uma cópia por igreja (id = 'louvor-a1b2c3d4', único e por igreja)
insert into departments (id, key, church_id, name, color, sigla, tooltip, tipo, ordem)
select t.key || '-' || left(c.id::text, 8), t.key, c.id,
       t.nome, t.cor, t.sigla, t.completo, 'normal', t.ordem
from churches c
cross join (values
  ('recepcao',   'Recepção',       '#2F8CFF', 'Rec', 'Recepção',       1),
  ('diaconato',  'Diaconato',      '#8B5CF6', 'Dia', 'Diaconato',      2),
  ('limpeza',    'Limpeza',        '#3DDC97', 'Limp','Limpeza',        3),
  ('louvor',     'Louvor',         '#FF8C1A', 'Louv','Louvor',         4),
  ('pregadores', 'Pregadores',     '#FF5C5C', 'Preg','Pregadores',     5),
  ('escola',     'Escola Sabatina','#FFC93C', 'ES',  'Escola Sabatina', 6),
  ('sonoplastia','Sonoplastia',    '#00D1C1', 'Som', 'Sonoplastia',    7)
) as t(key, nome, cor, sigla, completo, ordem)
on conflict (id) do nothing;

-- ===========================================================================
--  CONFERÊNCIA (rode e deve vir 7 igrejas · 51 agendas = 49 + 2 distritais)
-- ===========================================================================
-- select count(*) as igrejas from churches;
-- select count(*) as agendas from departments;
-- select church_id, count(*) from departments group by 1 order by 1 nulls first;
