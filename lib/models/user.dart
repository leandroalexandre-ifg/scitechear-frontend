/// Usuário logado, espelhando o `UserPublic` do backend: `user_id`, `email` e
/// `name`, e nada mais. Não há noção de papel/permissão em lugar nenhum do
/// servidor (confirmado com o backend em 07/09/2026); um `isAdmin` que sempre
/// valia `false` morava aqui e foi removido junto com o selo que ele
/// escondia na tela inicial.
class AppUser {
  final String id;
  final String name;
  final String email;

  const AppUser({
    required this.id,
    required this.name,
    required this.email,
  });
}
