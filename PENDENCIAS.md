# Pendências

> Itens combinados e **ainda não implementados**. Ao concluir, mover para "Concluídas".
> (As linhas citadas são as de 17/10/2026 e podem ter deslocado com as edições.)

---

## 1. Admin Local: não cadastrar administradores nem usuários de outra igreja

**Registrado em:** 17/10/2026 · **Status:** pendente

**O que foi pedido:**

1. O **Admin Local não pode** cadastrar usuário com nível **administrador** (Admin Distrital).
2. O **Admin Local não pode** cadastrar usuário **para outra igreja** — somente para a igreja em que ele está cadastrado.

**Onde mexer no `index.html`:**

| Ponto | Linha | Situação hoje |
|---|---|---|
| `#usNivel` (opções do select) | 939–944 | Oferece `admin_dist` e `admin_local` a qualquer um que abra o formulário |
| `fillIgrejas()` | 1422 | Preenche `#usIgreja` com **todas** as igrejas, sem filtrar pelo papel |
| `saveUser()` – alterando | 1554–1575 | `canManageUser(alvo)` confere só a igreja de destino **atual**; não impede trocar `dados.igreja` nem subir `dados.nivel` para `admin_dist` |
| `saveUser()` – cadastrando | 1576+ | Confere apenas duplicidade; **não** confere `dados.igreja === ROLES.admin_local.myChurch` nem `dados.nivel` |

**Regra sugerida** (quando `S.role==='admin_local'`):

- `#usIgreja` travado em `ROLES.admin_local.myChurch` — mesma ideia já usada no `#alSel` (linha 2305);
- `#usNivel` sem a opção `admin_dist`;
- validação **também** em `saveUser()`, não confiar só na interface.

**Backend – `supabase/functions/criar-usuario/index.ts`:**

- ✔ igreja já é validada: o admin_local só cria/exclui/atualiza na própria igreja (linhas 64, 83–86, 100–103);
- ⚠ **`nivel` não é validado**: é gravado pelo cliente direto em `public.users` (`index.html`, linha 1584). Confirmar se a RLS (ou uma trigger) impede um admin_local de gravar `nivel='admin_dist'`; se não impedir, essa checagem precisa entrar aqui.

---

## Concluídas

*(mover os itens para cá quando forem implementados)*
