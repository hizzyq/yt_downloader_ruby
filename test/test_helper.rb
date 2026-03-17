# test/test_helper.rb - Вспомогательные функции для тестов

require "fileutils"

# Цвета для вывода
GREEN = "\e[32m"
RED = "\e[31m"
YELLOW = "\e[33m"
BLUE = "\e[34m"
RESET = "\e[0m"

# Базовая тест-система
class TestCase
  def self.inherited(subclass)
    @test_classes ||= []
    @test_classes << subclass
  end

  def self.run_all
    @test_classes ||= []
    total_passed = 0
    total_failed = 0
    total_tests = 0

    puts "#{BLUE}Запуск всех тестов#{RESET}"
    puts "=" * 60

    @test_classes.each do |test_class|
      puts "\n#{YELLOW}#{test_class.name}#{RESET}"

      passed, failed = test_class.run
      total_passed += passed
      total_failed += failed
      total_tests += passed + failed
    end

    puts "\n" + "=" * 60
    puts "ИТОГО: #{GREEN}Пройдено: #{total_passed}#{RESET}, #{RED}Провалено: #{total_failed}#{RESET}"
    puts "Вердикт: #{total_failed == 0 ? GREEN + 'УСПЕХ' : RED + 'ПРОВАЛ'}#{RESET}"

    total_failed == 0
  end

  def self.run
    passed = 0
    failed = 0

    tests = instance_methods.grep(/^test_/).sort
    tests.each do |test_name|
      print "  #{test_name.to_s.gsub('test_', '').tr('_', ' ')}... "

      instance = new
      start_time = Time.now

      begin
        instance.setup if instance.respond_to?(:setup)
        instance.send(test_name)
        instance.teardown if instance.respond_to?(:teardown)

        puts "#{GREEN}OK#{RESET} (%.2fs)" % (Time.now - start_time)
        passed += 1
      rescue => e
        puts "#{RED}FAIL#{RESET}"
        puts "    #{RED}Ошибка: #{e.message}#{RESET}"
        puts "    #{e.backtrace.first(3).join("\n    ")}"
        failed += 1
      end
    end

    [passed, failed]
  end

  def assert(condition, message = "Assertion failed")
    raise message unless condition
  end

  def assert_equal(expected, actual, message = nil)
    message ||= "Ожидалось #{expected.inspect}, получено #{actual.inspect}"
    raise message unless expected == actual
  end

  def assert_raises(error_class, message = nil, &block)
    begin
      block.call
    rescue error_class => e
      return e
    rescue => e
      raise "Ожидалось исключение #{error_class}, но получено #{e.class}: #{e.message}"
    else
      raise "Ожидалось исключение #{error_class}, но исключение не было вызвано"
    end
  end

  def assert_match(pattern, string, message = nil)
    message ||= "Строка #{string.inspect} не соответствует паттерну #{pattern.inspect}"
    raise message unless pattern =~ string
  end

  def refute(condition, message = "Assertion failed")
    raise message if condition
  end

  def refute_equal(expected, actual, message = nil)
    message ||= "Ожидалось не #{expected.inspect}, но получено #{actual.inspect}"
    raise message if expected == actual
  end
end

# Временные файлы для тестов
module TestHelpers
  def create_temp_file(content = "test", extension = ".txt")
    FileUtils.mkdir_p("tmp/test")
    path = "tmp/test/temp_#{Time.now.to_i}_#{rand(1000)}#{extension}"
    File.write(path, content)
    path
  end

  def cleanup_temp_files
    FileUtils.rm_rf("tmp/test")
  end
end

