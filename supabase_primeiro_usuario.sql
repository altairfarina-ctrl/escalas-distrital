-- ===========================================================================
--  PRIMEIRO USUÁRIO (Etapa 2 – login + leitura)        08/10
--  Rodar DEPOIS de criar o usuário no dashboard:
--    Authentication → Users → Add user
--      Email:    admin@escalas.distrital.app
--      Password: (a que você escolher, mín. 8 caracteres)
--      ☐ Confirm email   ← DESMARCADO (Authentication → Sign In / Providers → Email)
--
--  O Supabase Auth guarda o login com e-mail; aqui embaixo a gente só cria a
--  LINHA DE PERFIL em public.users apontando para esse auth.users.id.
-- ===========================================================================
insert into public.users (auth_id, login, nome, nivel, zap, church_id)
select u.id,
       'admin',
       'Admin Distrital',
       'admin_dist',
       '',
       null                       -- null = distrital: vê TODAS as igrejas
from auth.users u
where lower(u.email) = 'admin@escalas.distrital.app'
  and not exists (
        select 1 from public.users p where p.auth_id = u.id
      )
on conflict (auth_id) do nothing;

-- Conferir que nasceu certo:
select p.login, p.nome, p.nivel,
       case when p.church_id is null then '(distrital)' else 'igreja' end as igreja,
       p.auth_id
from public.users p;
