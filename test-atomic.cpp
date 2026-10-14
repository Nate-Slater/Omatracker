// Integration regression for FileView's QSaveFile backend. No post-save chmod.
// Build: c++ -fPIC test-atomic.cpp -o /tmp/omatracker-atomic $(pkg-config --cflags --libs Qt6Core)
// Run: /tmp/omatracker-atomic ./restrict-store.sh
#include <QCoreApplication>
#include <QFile>
#include <QProcess>
#include <QSaveFile>
#include <QTemporaryDir>
#include <cstdio>
#include <cstdlib>
#include <sys/stat.h>

static void check(bool ok, const char *message) {
  if (!ok) { std::fprintf(stderr, "%s\n", message); std::exit(1); }
}

static mode_t mode(const QString &path) {
  struct stat st {};
  check(::stat(QFile::encodeName(path).constData(), &st) == 0, "stat failed");
  return st.st_mode & 07777;
}

int main(int argc, char **argv) {
  QCoreApplication app(argc, argv);
  check(argc == 2, "pass the path to restrict-store.sh");
  QTemporaryDir scratch;
  check(scratch.isValid(), "temporary directory failed");
  const auto dir = scratch.path() + "/omatracker";
  const auto path = dir + "/data.json";
  for (mode_t mask : {0022, 0000, 0077}) {
    ::umask(mask);
    QFile::remove(path);
    for (int i = 0; i < 3; ++i) {
      check(QProcess::execute("bash", {QString::fromLocal8Bit(argv[1]), "prepare", dir, path}) == 0,
            "permission preparation failed");
      check(mode(dir) == 0700 && mode(path) == 0600, "unsafe mode before writing");
      QSaveFile save(path);
      check(save.open(QIODevice::WriteOnly), "QSaveFile open failed");
      struct stat st {};
      check(::fstat(save.handle(), &st) == 0 && (st.st_mode & 07777) == 0600,
            "atomic temporary file not private BEFORE writing");
      const auto data = QByteArray("{\"private\":") + QByteArray::number(i) + "}\n";
      check(save.write(data) == data.size(), "write failed");
      check(::fstat(save.handle(), &st) == 0 && (st.st_mode & 07777) == 0600,
            "atomic temporary file not private AFTER writing");
      check(save.commit(), "commit failed");
      check(mode(path) == 0600, "committed history not private");
      QFile file(path);
      check(file.open(QIODevice::ReadOnly) && file.readAll() == data, "content mismatch");
    }
  }
  // The owner-only default ACL also protects a new QSaveFile target if an
  // owner removes the seed between preparation and the write.
  QFile::remove(path);
  ::umask(0000);
  QSaveFile save(path);
  check(save.open(QIODevice::WriteOnly), "new target open failed");
  struct stat st {};
  check(::fstat(save.handle(), &st) == 0 && (st.st_mode & 07777) == 0600,
        "new atomic temporary file not private");
  check(save.write("private") == 7 && save.commit(), "new target commit failed");
  check(mode(path) == 0600, "new target did not inherit owner-only ACL");
  std::puts("PASS: private first writes, replacements, and temporary files under umask 022/000/077");
}
