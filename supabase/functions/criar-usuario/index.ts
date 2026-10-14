// ==========================================================================
// Edge Function "criar-usuario" — Agenda Distrital (Distrito Ivailândia/ANP)
//
// Cria / exclui / redefini contas no Supabase Auth pela ADMIN API (chave de
// serviço), que NÃO tem o limite de "contas novas por hora" do signUp
// público do plano gratuito, e também resolve a conta órfã que ficava
// depois de excluir um usuário pelo sistema.
//
// Ações aceitas (POST, JSON no corpo):
//   criar   {login, senha, church_id}  -> {auth_id}
//   excluir {auth_id}                  -> {ok:true}
//   senha   {auth_id, senha}           -> {ok:true}
//
// Segurança: só atende quem tem sessão válida E cadastro em public.users
// com nível admin_dist ou admin_local (Admin Local só na própria igreja).
//
// Publicar (uma vez):
//   supabase functions deploy criar-usuario --project-ref mjnwhohloafxfdsbltbl
// ==========================================================================
import { createClient } from "npm:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const EMAIL_DOM = "@escalas.distrital.app";   // e-mail sintético (mesmo do index.html)

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status, headers: { ...CORS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const admin = createSvc();
    if (!admin) return json({ erro: "SUPABASE_SERVICE_ROLE_KEY não configurada" }, 500);

    // ---- quem chamou? (o supabase-js manda o token do usuário no cabeçalho) ----
    const tok = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    const { data: ud, error: ue } = await admin.auth.getUser(tok);
    if (ue || !ud || !ud.user) return json({ erro: "sessão inválida" }, 401);

    // ---- perfil do chamador (nível/igreja) ----
    const { data: perfil } = await admin
      .from("users").select("nivel,church_id").eq("auth_id", ud.user.id).maybeSingle();
    const nivel = perfil && perfil.nivel;
    if (nivel !== "admin_dist" && nivel !== "admin_local")
      return json({ erro: "somente administradores criam ou excluem usuários" }, 403);

    const b = await req.json().catch(() => ({}));
    const acao = String(b.acao || "");

    // ---- cria ----
    if (acao === "criar") {
      const login = String(b.login || "").trim().toLowerCase();
      const senha = String(b.senha || "");
      const igreja = b.church_id || null;
      if (!login || !/^[a-z0-9._-]+$/.test(login))
        return json({ erro: "login inválido (use só letras, números, . _ -)" }, 400);
      if (senha.length < 6) return json({ erro: "a senha precisa de pelo menos 6 caracteres" }, 400);
      if (nivel === "admin_local" && String(perfil.church_id) !== String(igreja))
        return json({ erro: "Admin Local cadastra usuários só na própria igreja" }, 403);
      const email = login + EMAIL_DOM;
      const { data: nu, error } = await admin.auth.admin.createUser({
        email, password: senha, email_confirm: true,   // já entra confirmado
      });
      if (error) {
        const m = String(error.message || "");
        return json({ erro: /already|registered/i.test(m)
          ? "esse login já tem uma conta — use outro apelido"
          : "não deu para criar a conta: " + m }, 400);
      }
      return json({ auth_id: nu.user.id });
    }

    // ---- exclui (cadastro + conta Auth) ----
    if (acao === "excluir") {
      const authId = String(b.auth_id || "");
      if (!authId) return json({ erro: "auth_id ausente" }, 400);
      if (nivel === "admin_local") {
        const { data: alvo } = await admin.from("users")
          .select("church_id").eq("auth_id", authId).maybeSingle();
        if (!alvo || String(alvo.church_id) !== String(perfil.church_id))
          return json({ erro: "Admin Local exclui usuários só da própria igreja" }, 403);
      }
      const { error } = await admin.auth.admin.deleteUser(authId);
      if (error) return json({ erro: "não deu para apagar a conta de acesso: " + error.message }, 400);
      return json({ ok: true });
    }

    // ---- redefini senha (para a v2 de "🔑 Minha senha") ----
    if (acao === "senha") {
      const authId = String(b.auth_id || "");
      const senha = String(b.senha || "");
      if (!authId || senha.length < 6)
        return json({ erro: "informe o usuário e uma senha de pelo menos 6 caracteres" }, 400);
      if (nivel === "admin_local") {
        const { data: alvo } = await admin.from("users")
          .select("church_id").eq("auth_id", authId).maybeSingle();
        if (!alvo || String(alvo.church_id) !== String(perfil.church_id))
          return json({ erro: "Admin Local redefine senha só na própria igreja" }, 403);
      }
      const { error } = await admin.auth.admin.updateUserById(authId, { password: senha });
      if (error) return json({ erro: "não deu para trocar a senha: " + error.message }, 400);
      return json({ ok: true });
    }

    return json({ erro: "ação desconhecida: " + acao }, 400);
  } catch (e) {
    return json({ erro: (e && e.message) || "erro na função" }, 500);
  }
});

// cliente Supabase com a chave de serviço (injetada automaticamente no deploy)
function createSvc() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return null;
  return createClient(url, key, { auth: { persistSession: false } });
}
