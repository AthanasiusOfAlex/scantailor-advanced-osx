class ScantailorAdvanced < Formula
  desc "Interactive post-processing tool for scanned pages (Advanced)"
  homepage "https://github.com/ScanTailor-Advanced/scantailor-advanced"
  url "https://github.com/ScanTailor-Advanced/scantailor-advanced/archive/refs/tags/v1.2.1.tar.gz"
  sha256 "9eb20238378151e32055f8f5c6d67cf0b4c93b77eba3f11266656879c41ac009"
  license "GPL-3.0-or-later"
  head "https://github.com/ScanTailor-Advanced/scantailor-advanced.git", branch: "master"

  depends_on "cmake" => :build
  depends_on "boost"
  depends_on "jpeg-turbo"
  depends_on "libpng"
  depends_on "libtiff"
  depends_on "qt"

  def install
    system "cmake", "-S", ".", "-B", "build",
                    "-DBUILD_TESTS=OFF",
                    *std_cmake_args
    system "cmake", "--build", "build"
    system "cmake", "--install", "build"

    # Provide 'scantailor' symlink for convenience and compatibility
    bin.install_symlink "scantailor-advanced" => "scantailor"
  end

  patch :DATA

  test do
    assert_path_exists bin/"scantailor-advanced"
    assert_path_exists bin/"scantailor"
  end
end

__END__
diff --git a/src/app/MainWindow.cpp b/src/app/MainWindow.cpp
--- a/src/app/MainWindow.cpp
+++ b/src/app/MainWindow.cpp
@@ -1314,6 +1314,18 @@ void MainWindow::filterResult(const BackgroundTaskPtr& task, const FilterResultP
     }
   }
 
+  // Keep the worker pool fed before doing thumbnail invalidation and other
+  // GUI-thread work in updateUI().
+  if (isBatchProcessingInProgress() && !m_batchQueue->allProcessed()) {
+    do {
+      const BackgroundTaskPtr nextTask(m_batchQueue->takeForProcessing());
+      if (!nextTask) {
+        break;
+      }
+      m_workerThreadPool->submitTask(nextTask);
+    } while (m_workerThreadPool->hasSpareCapacity());
+  }
+
   // This needs to be done even if batch processing is taking place,
   // for instance because thumbnail invalidation is done from here.
   result->updateUI(this);
diff --git a/src/core/DeviationProvider.h b/src/core/DeviationProvider.h
--- a/src/core/DeviationProvider.h
+++ b/src/core/DeviationProvider.h
@@ -8,8 +8,17 @@
 
 #include <cmath>
 #include <functional>
+#include <mutex>
 #include <unordered_map>
 
+// Threading contract: writers (worker threads, via the owning Settings object)
+// and readers (GUI thread: CacheDrivenTask::process during thumbnail creation,
+// OrderByDeviationProvider during sorts) may call into this class
+// concurrently. All state — the key/value map and the lazily recomputed
+// mean/stddev cache — is guarded by an internal mutex, so the const getters
+// are safe to call without external locking. The computeValueByKey callback
+// is invoked OUTSIDE the internal mutex (callers typically invoke addOrUpdate
+// while holding their own Settings mutex, which the callback may rely on).
 template <typename K, typename Hash = std::hash<K>>
 class DeviationProvider {
   DECLARE_NON_COPYABLE(DeviationProvider)
@@ -33,12 +42,17 @@ public:
   void setComputeValueByKey(const std::function<double(const K&)>& computeValueByKey);
 
  protected:
+  // Recomputes the cached statistics. Must be called with m_mutex held.
   void update() const;
 
  private:
   std::function<double(const K&)> m_computeValueByKey;
   std::unordered_map<K, double, Hash> m_keyValueMap;
 
+  // Guards m_keyValueMap and the cached values below (see the threading
+  // contract at the top of the class).
+  mutable std::mutex m_mutex;
+
   // Cached values.
   mutable bool m_needUpdate = false;
   mutable double m_meanValue = 0.0;
@@ -52,6 +66,7 @@ public:
 
 template <typename K, typename Hash>
 bool DeviationProvider<K, Hash>::isDeviant(const K& key, double coefficient, double threshold, bool defaultVal) const {
+  const std::lock_guard<std::mutex> lock(m_mutex);
   if (m_keyValueMap.find(key) == m_keyValueMap.end()) {
     return false;
   }
@@ -71,6 +86,7 @@ bool DeviationProvider<K, Hash>::isDeviant(const K& key, double coefficient, dou
 
 template <typename K, typename Hash>
 double DeviationProvider<K, Hash>::getDeviationValue(const K& key) const {
+  const std::lock_guard<std::mutex> lock(m_mutex);
   if (m_keyValueMap.find(key) == m_keyValueMap.end()) {
     return -1.0;
   }
@@ -89,13 +105,24 @@ double DeviationProvider<K, Hash>::getDeviationValue(const K& key) const {
 
 template <typename K, typename Hash>
 void DeviationProvider<K, Hash>::addOrUpdate(const K& key) {
+  // Invoke the callback outside the internal mutex (threading contract),
+  // via a copy taken under the lock.
+  std::function<double(const K&)> computeValueByKey;
+  {
+    const std::lock_guard<std::mutex> lock(m_mutex);
+    computeValueByKey = m_computeValueByKey;
+  }
+  const double value = computeValueByKey(key);
+
+  const std::lock_guard<std::mutex> lock(m_mutex);
   m_needUpdate = true;
 
-  m_keyValueMap[key] = m_computeValueByKey(key);
+  m_keyValueMap[key] = value;
 }
 
 template <typename K, typename Hash>
 void DeviationProvider<K, Hash>::addOrUpdate(const K& key, const double value) {
+  const std::lock_guard<std::mutex> lock(m_mutex);
   m_needUpdate = true;
 
   m_keyValueMap[key] = value;
@@ -103,6 +130,7 @@ void DeviationProvider<K, Hash>::addOrUpdate(const K& key, const double value) {
 
 template <typename K, typename Hash>
 void DeviationProvider<K, Hash>::remove(const K& key) {
+  const std::lock_guard<std::mutex> lock(m_mutex);
   m_needUpdate = true;
 
   if (m_keyValueMap.find(key) == m_keyValueMap.end()) {
@@ -147,11 +175,13 @@ void DeviationProvider<K, Hash>::update() const {
 
 template <typename K, typename Hash>
 void DeviationProvider<K, Hash>::setComputeValueByKey(const std::function<double(const K&)>& computeValueByKey) {
+  const std::lock_guard<std::mutex> lock(m_mutex);
   this->m_computeValueByKey = std::move(computeValueByKey);
 }
 
 template <typename K, typename Hash>
 void DeviationProvider<K, Hash>::clear() {
+  const std::lock_guard<std::mutex> lock(m_mutex);
   m_keyValueMap.clear();
 
   m_needUpdate = false;
diff --git a/src/core/WorkerThreadPool.cpp b/src/core/WorkerThreadPool.cpp
--- a/src/core/WorkerThreadPool.cpp
+++ b/src/core/WorkerThreadPool.cpp
@@ -57,6 +57,10 @@ void WorkerThreadPool::submitTask(const BackgroundTaskPtr& task) {
         }
       } catch (const std::bad_alloc&) {
         OutOfMemoryHandler::instance().handleOutOfMemorySituation();
+      } catch (const std::exception& e) {
+        qWarning("Exception in worker thread: %s", e.what());
+      } catch (...) {
+        qWarning("Unknown exception in worker thread");
       }
     }
 
@@ -85,6 +89,12 @@ void WorkerThreadPool::updateNumberOfThreads() {
   }
 
   int numThreads = m_settings.value("settings/batch_processing_threads", maxThreads).toInt();
+  bool overrideOk = false;
+  const int overrideThreads = qEnvironmentVariableIntValue("SCANTAILOR_BATCH_THREADS", &overrideOk);
+  if (overrideOk) {
+    numThreads = overrideThreads;
+  }
+  numThreads = std::max(1, numThreads);
   numThreads = std::min(numThreads, maxThreads);
   m_pool->setMaxThreadCount(numThreads);
 }
