# Resposta do frontend — `participant_id`, teste conjunto e `/meetings`

**Data:** 07/09/2026
**Repositório:** SciTech-frontend, branch `main`
**Responde a:** "Pedidos ao app", backend `main` `e7d8ad1`

Resposta ao item 1 primeiro, porque vocês estavam certos em mandá-lo mesmo
que sozinho: **as duas respostas são "não"**, e o segundo caso era pior do
que a pergunta supunha. A parte que o app podia consertar sozinho está
consertada nesta rodada; a parte que depende de vocês está descrita com o que
achamos que ajuda a projetar a saída.

`flutter analyze` limpo; suíte em **34 testes** (eram 26), todos passando.

---

## 1. Não, os `participant_id` não são estáveis

### 1.1. Sobrevivem a reinstalar o app ou trocar de aparelho? **Não.**

O id é gerado no cadastro local do participante, em
`lib/screens/participants_screen.dart`:

```dart
final participant = Participant(
  id: DateTime.now().microsecondsSinceEpoch.toString(),
  ...
);
```

e existe em exatamente um lugar: a chave
`u<user_id>:registered_participants` do `shared_preferences` do aparelho.
Desinstalar o app apaga; um aparelho novo nunca teve.

A consequência é pior do que "às vezes sobra um perfil": **cada reinstalação
órfã o conjunto inteiro de perfis daquela conta.** O usuário reinstala, não vê
mais participante nenhum, recadastra as mesmas pessoas, recebe ids novos, e
sobe amostras novas. As antigas continuam lá, com nomes de pessoas reais
dentro, e nem o app nem o usuário têm mais como alcançá-las.

O mesmo vale para a segunda instalação de um usuário que use dois aparelhos:
não é "o mesmo participante nos dois", são dois perfis independentes para a
mesma pessoa.

Mais duas propriedades que talvez importem para o desenho da saída:

- **O id é único por acaso de relógio, não por construção.** Dois aparelhos da
  mesma conta cadastrando um participante no mesmo microssegundo colidem
  dentro do namespace daquele usuário — duas pessoas dividiriam um diretório
  de voz. É improbabilíssimo, mas não é uma garantia que alguém tenha dado.
- **Não há segunda cópia do id no app.** O histórico de reuniões guarda
  `participantNames`, não ids. Um perfil esquecido não é recuperável nem
  vasculhando o resto do armazenamento local.

### 1.2. Apagar um participante chama o `DELETE`? **Sim, mas vazava.**

`ParticipantService.remove()` sempre chamou
`DELETE /participants/{id}/voice-profile`. O problema é que era best-effort e
o registro local sumia **de qualquer jeito**: se a chamada falhasse — sem
rede, servidor fora, sessão expirada —, o id ia embora junto e o perfil ficava
órfão para sempre. O usuário via um aviso, mas não havia nada que ele pudesse
fazer: o id já não existia mais.

**Corrigido nesta rodada.** Quando o `DELETE` falha, o id vai para uma fila de
exclusões pendentes (`u<user_id>:pending_voice_profile_deletions`), que é
retomada toda vez que a tela de participantes abre com conexão. Um 404 encerra
a pendência — o objetivo era o perfil não existir, e ele não existe. Cinco
testes cobrem isso em `test/voice_profile_deletion_test.dart`, incluindo o
escopo por usuário da fila.

Isso fecha o vazamento **novo** por esse caminho. Não recupera nada do que já
acumulou, nem cobre o caso da reinstalação — esses continuam com vocês.

### 1.3. Duas coisas que podem ajudar no desenho

**Os ids órfãos não estão todos perdidos do lado de vocês.** Todo upload manda
`participants` como `[{id, name}]`, então o registro de cada job guarda os ids
que aquele usuário usou — inclusive os de instalações antigas. Dá para
reconciliar `storage/voices/<user_id>/*` contra os ids referenciados nos jobs
daquele usuário sem nenhuma rota nova: o que estiver no disco e não aparecer
em job nenhum é, com alta confiança, resto de instalação anterior. Não é
perfeito (um participante cadastrado e nunca usado em reunião não aparece),
mas cobre a maior parte do acúmulo e serve como faxina única.

**Das duas saídas que vocês citaram, preferimos a rota de listagem.**
Um `GET /participants` (ou `GET /voice-profiles`) escopado por usuário
resolve as duas metades: dá para limpar o que já acumulou **e** dá ao app como
reconciliar depois de uma reinstalação — inclusive oferecendo ao usuário
"encontramos 3 perfis de voz nesta conta que este aparelho não conhece:
manter ou apagar?". **Se essa rota existir, a gente consome.**

Derivar a chave do nome (um hash de `user_id` + nome normalizado) resolveria a
reinstalação sem rota nova, mas achamos pior: renomear participante mudaria o
id, dois homônimos colidiriam, e passaria a haver o nome de uma pessoa
embutido num caminho de diretório. Só faz sentido se a rota de listagem for
cara por algum motivo que a gente não enxerga daqui.

Se vocês fizerem a rota, o único pedido é que ela devolva, além do id, algo
que o usuário reconheça — o `name` que veio junto na amostra de voz basta.
Uma lista de ids crus não dá para mostrar a ninguém.

---

## 2. Teste conjunto — concordamos com a ordem; a data vem em seguida

Concordamos com a prioridade e com a ordem proposta: **o teste conjunto antes
da migração do histórico.** O argumento é o certo — validar autenticação,
upload, WebSocket e pipeline com uma causa possível por bug, em vez de cinco.

**A data ainda não está fechada; confirmamos em seguida.** Não é hesitação
sobre fazer, é só agenda: o teste precisa de um Android físico e de alguém em
frente aos dois lados ao mesmo tempo.

Do lado do app não há nada pendente para o teste acontecer — o que estava
bloqueando (o 403 no cadastro) foi resolvido na rodada anterior. Quando
marcarmos, precisamos de vocês só com a API e o worker de pé.

Continua valendo o checklist: duas contas `@ifg.edu.br`, não errar o domínio
(10 falhas travam o **IP** por 1h, e com `adb reverse` isso é o aparelho
inteiro) e não errar senha 5 vezes na mesma conta.

---

## 3. Migração do `/meetings` — não começamos, de propósito

Seguindo a ordem que vocês mesmos sugeriram, a migração fica para depois do
teste. Sobre os três pontos:

- **Confirmação antes de remover.** Já existe um diálogo de confirmação, mas o
  texto dele diz *"será removida do seu histórico local"* — que vira mentira
  no dia da migração. Anotado que a mudança não é só de parser: o texto passa
  a ter que dizer que o áudio e o resultado são apagados do servidor, sem
  desfazer. Vai junto com a migração, não antes, senão o app avisa hoje de
  algo que ainda não faz.
- **409 no `DELETE` durante o processamento.** Anotado, vai com a migração.
- **O 4404 novo do WebSocket: já está tratado.** Este a gente adiantou porque
  não dependia do resto e o comportamento anterior era ruim de qualquer
  maneira. Antes, um 404 no polling não era distinguido de falha de rede:
  quatro tentativas ao longo de 12 segundos e então *"Sem conexão com o
  servidor. Verifique sua conexão"* — mandando o usuário procurar defeito na
  rede dele, que estava perfeita. Agora o 404 é terminal na primeira resposta
  e vira **"Reunião removida — esta reunião não está mais no servidor. Ela
  pode ter sido removida em outro aparelho."**, com o botão "Tentar
  novamente" removido dessa tela, já que só produziria o mesmo 404.

  Mantivemos o polling como quem decide: o WS fecha com 4404, cai no polling,
  e é a resposta HTTP que classifica. Um lugar só decidindo, e que também
  cobre o 404 chegando sem WS nenhum.

---

## 4. Os dois detalhes — obrigado, os dois eram armadilha

**Paginação.** Não tínhamos visto. Vamos paginar de verdade (carregar mais ao
rolar), não subir o `limit` para 200 e torcer — 200 adia o problema em vez de
resolver, e some do mesmo jeito, em silêncio, para quem passar disso.

**Offline.** Este é o ponto mais importante dos dois, e a decisão é: **a lista
vinda do servidor passa a ser gravada localmente como cache de leitura.** A
tela abre com o cache (instantâneo, funciona sem rede), dispara a busca e se
atualiza quando o servidor responde; sem conectividade, mostra a última lista
conhecida com um aviso de que pode estar desatualizada. Sem rede e sem cache
— aparelho novo, primeiro uso —, aí sim uma tela vazia explicando que precisa
de conexão, que é honesto.

É o mesmo padrão que já usamos para o perfil de voz (§3.1 da resposta
anterior): estado local primeiro, servidor manda, falha de rede nunca é
tratada como ausência. O que não vai acontecer é o histórico virar tela em
branco no primeiro corredor sem sinal.

Registramos que isso **não** é o cache de resultado, que continua existindo em
separado e cobrindo a reabertura de uma reunião específica sem rede.

---

## 5. Resumo

| Item | Situação |
|---|---|
| 1 — `participant_id` estável? | ❌ **não**, nem a reinstalação nem a troca de aparelho; §1.1 |
| 1 — `DELETE` ao apagar participante? | ⚠️ sim, mas vazava quando falhava — ✅ **corrigido** (fila de pendentes, 5 testes) |
| 1 — limpeza do que já acumulou | 🔜 com vocês; §1.3 traz uma reconciliação sem rota nova e nossa preferência por `GET /participants` |
| 2 — teste conjunto | ✅ ordem aceita (antes da migração); **data a confirmar** |
| 3 — confirmação ao remover | 🔜 com a migração (o texto atual vira mentira, anotado) |
| 3 — 409 no `DELETE` | 🔜 com a migração |
| 3 — 4404 / 404 = "reunião removida" | ✅ **feito** nesta rodada, com teste |
| 4 — paginação | ✅ anotado: paginar de verdade, não subir o `limit` |
| 4 — lista offline | ✅ decidido antes de migrar: cache de leitura da lista |
