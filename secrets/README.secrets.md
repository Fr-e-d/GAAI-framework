
  # Chiffrer le fichier avec un mot de passe :
  openssl enc -aes-256-cbc -pbkdf2 -in secrets/staging.secrets.txt -out secrets/staging.secrets.enc
  # → Enter a password (choisis-en un fort, stocke-le dans 1Password)

  # Déchiffrer ou Vérifie que le déchiffrement fonctionne :
  openssl enc -aes-256-cbc -pbkdf2 -d -in secrets/staging.secrets.enc
  # → Enter a password
  # → doit afficher le contenu en clair
  
  # Supprimer le plaintext
  rm secrets/staging.secrets.txt

  # Committer uniquement le .enc
  git add secrets/staging.secrets.enc
  git commit -m "chore: add encrypted staging secrets"
  git push origin production